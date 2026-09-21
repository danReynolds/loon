import 'dart:io';
import 'package:path/path.dart' as p;
import 'tool_support.dart';
import 'scoped_traversal_variants.dart';

const variantNames = [
  'baseline',
  'store',
  'identity',
  'combined',
  'touch',
  'visitor',
  'document_before',
  'document_before_paths',
  'document_paths',
  'path_cache_lru',
  'path_cache_recent',
  'delete_recent',
  'batch_buckets',
  'batch_clean',
  'scoped_clean',
  'scoped_guard',
  'scoped_cursor',
  'scoped_cursor_simple',
  'scoped_cursor_cleanup',
  'scoped_collections',
  'scoped_collections_recent',
];

/// Fail-closed transforms applied only to disposable copies of the library.
void configureVariant(String destination, String variant) {
  if (!variantNames.contains(variant)) throw ArgumentError.value(variant);
  File file(String path) => File(p.join(destination, path));
  configureScopedTraversal(file, variant);
  if (['path_cache_lru', 'path_cache_recent'].contains(variant)) {
    var draft = file('benchmark/value_store/path_cache_draft.dart')
        .readAsStringSync()
        .replaceFirst("import 'dart:collection';", "part of '../loon.dart';");
    for (final name in [
      'ParsedStorePath',
      'PathPlanCache',
      'BoundedPathCache',
      'RecentPathCache',
      'PathOwner'
    ]) {
      draft = draft.replaceAll(name, '_Profile$name');
    }
    final type = variant == 'path_cache_lru'
        ? '_ProfileBoundedPathCache'
        : '_ProfileRecentPathCache';
    file('lib/store/profile_paths.dart')
        .writeAsStringSync('$draft\nfinal _profilePathCache = $type();\n');
    final library = file('lib/loon.dart');
    var source = replaceOnce(
        library.readAsStringSync(),
        "part 'store/base_value_store.dart';",
        "part 'store/profile_paths.dart';\npart 'store/base_value_store.dart';");
    source = replaceOnce(source, '    // Clear the store.\n',
        '    _profilePathCache.clear();\n    // Clear the store.\n');
    library.writeAsStringSync(source);
    final base = file('lib/store/base_value_store.dart');
    source = base.readAsStringSync();
    final start = source.indexOf('  T? get(String path) {');
    final guard = source.indexOf('    if (_store.isEmpty) return null;', start);
    if (start < 0 || guard < 0) throw StateError('Update cached-get transform');
    final end = guard + '    if (_store.isEmpty) return null;'.length;
    source = source.replaceRange(end, end, '''
    final parsed = _profilePathCache.lookup(path);
    if (parsed != null) return parsed.read<T>(_store);
''');
    base.writeAsStringSync(source);
  }
  if (['document_before', 'document_before_paths'].contains(variant)) {
    _beforeDocumentChanges(file);
  }
  if (['document_paths', 'document_before_paths'].contains(variant)) {
    _rebuildDocumentsFromPaths(file('lib/dependency_manager.dart'));
  }
  if (['baseline', 'identity'].contains(variant)) {
    // Restore up-front splitting for the exact getter and the shared flat reads.
    final base = file('lib/store/base_value_store.dart');
    var source = base.readAsStringSync();
    final start =
        source.indexOf('  Object? _lookup(String path, _Lookup part) {');
    final end = source.indexOf('\n  }\n', start);
    if (start < 0 || end < 0) throw StateError('Update lookup transform');
    source = source.replaceRange(
        start, end + 4, '''  Object? _lookup(String path, _Lookup part) {
    final segments = path.split(delimiter);
    final last = segments.removeLast();
    Map? node = _store;
    for (final segment in segments) {
      if (node == null) break;
      node = node[segment];
    }
    if (node == null) return null;
    return switch (part) {
      _Lookup.node => node[last],
      _Lookup.parent => (node, last),
      _Lookup.path => node[_values]?[last] != null || node[last] != null,
    };
  }
''');
    final getStart = source.indexOf('  T? get(String path) {');
    final getEnd =
        source.indexOf('\n  /// Returns a map of all values', getStart);
    if (getStart < 0 || getEnd < 0) throw StateError('Update get transform');
    source = source.replaceRange(getStart, getEnd, '''  T? get(String path) {
    final segments = path.split(delimiter);
    final last = segments.removeLast();
    Map? node = _store;
    for (final segment in segments) {
      if (node == null) break;
      node = node[segment];
    }
    return node?[_values]?[last];
  }
''');
    base.writeAsStringSync(source);
    for (final name in ['value_store', 'value_ref_store']) {
      final target = file('lib/store/$name.dart');
      target.writeAsStringSync(replaceOnce(target.readAsStringSync(),
          '    if (_store.isEmpty) return;\n\n', ''));
    }
  }
  if (['baseline', 'store'].contains(variant)) {
    final target = file('lib/document.dart');
    var source = replaceOnce(
        target.readAsStringSync(),
        'late final int hashCode = Object.hash(parent, id);',
        'int get hashCode => Object.hash(parent, id);');
    source = replaceOnce(
        source,
        r"late final String path = id.isEmpty ? parent : '${parent}__$id';",
        r"String get path => id.isEmpty ? parent : '${parent}__$id';");
    target.writeAsStringSync(source);
  }
  if (variant == 'touch') {
    final target = file('lib/broadcast_manager.dart');
    var source = target.readAsStringSync();
    final start = source.indexOf('  void _broadcastDependents(');
    final end = source.indexOf('  void _deleteRef(', start);
    if (start < 0 || end < 0) throw StateError('Update touch transform');
    source = source.replaceRange(start, end, '''  void _broadcastDependents(
    StoreReference ref, {
    bool recursive = false,
  }) {
    final dependents = Loon._instance.dependencyManager
        .getDependents(ref, recursive: recursive);
    if (dependents != null) {
      for (final doc in dependents) {
        _touchDependent(doc);
      }
    }
  }

  void _touchDependent(Document doc) {
    final path = doc.path;
    if (eventStore.hasValue(path)) return;
    observerValueStore.delete(path, recursive: false);
    observerValueStore.delete(doc.parent, recursive: false);
    eventStore.write(path, BroadcastEvents.touched);
    _broadcastDependents(doc);
  }

''');
    target.writeAsStringSync(source);
  }
  if (variant == 'visitor') {
    final draft =
        file('benchmark/value_store/visitor_draft.dart').readAsStringSync();
    final start = draft.indexOf('void visitValues<T>(');
    if (start < 0) throw StateError('Update visitor transform');
    final body = draft
        .substring(draft.indexOf('{', start))
        .replaceFirst('final root = store.inspect();', 'final root = _store;');
    final target = file('lib/store/value_store.dart');
    final source = target.readAsStringSync();
    final end = source.lastIndexOf('}');
    target.writeAsStringSync(source.replaceRange(end, end,
        '  void forEachValueUnder(String path, void Function(T) visit) $body\n'));
    final manager = file('lib/dependency_manager.dart');
    final text = manager.readAsStringSync();
    final from =
        text.indexOf('    final entries = _dependencies.extractValues(path);');
    final to = text.indexOf('\n  }\n\n  void deleteDocument', from);
    if (from < 0 || to < 0) throw StateError('Update deletion transform');
    // Keep the caller's cleanup algorithm (including operation-local reuse),
    // changing only snapshot extraction into callback consumption.
    var cleanupBody = replaceOnce(
        text.substring(from, to),
        '''    final entries = _dependencies.extractValues(path);
    _dependencies.delete(path);

''',
        '');
    cleanupBody = replaceOnce(cleanupBody, '    for (final entry in entries) {',
        '    _dependencies.forEachValueUnder(path, (entry) {');
    if (!cleanupBody.endsWith('    }')) throw StateError('Update visitor loop');
    cleanupBody = '${cleanupBody.substring(0, cleanupBody.length - 5)}    });\n'
        '    _dependencies.delete(path);';
    manager.writeAsStringSync(text.replaceRange(from, to, cleanupBody));
  }
}

/// The working library immediately before the four document/allocation changes.
/// Keeps earlier get guards, retained entries and document identity caching.
void _beforeDocumentChanges(File Function(String) file) {
  for (final (name, fields) in [
    ('document', 'parent, id'),
    ('collection', 'parent, name'),
    ('document_snapshot', 'doc, data'),
    ('document_change_snapshot', 'doc, event, data, prevData'),
  ]) {
    final target = file('lib/$name.dart');
    var source = replaceOnce(target.readAsStringSync(), 'Object.hash($fields)',
        'Object.hashAll([$fields])');
    if (name == 'document' || name == 'collection') {
      source = replaceOnce(
          source,
          'final (parent, id) = _splitReferencePath(path);',
          'final [...pathSegments, id] = path.split(_BaseValueStore.delimiter);');
      final type = name == 'document' ? 'Document' : 'Collection';
      source = replaceOnce(source, 'return $type<S>(\n      parent,\n      id,',
          'return $type<S>(\n      pathSegments.join(_BaseValueStore.delimiter),\n      id,');
    }
    if (name == 'collection') {
      source = replaceOnce(source, r'''  late final String path =
      parent.isEmpty || parent == _rootKey ? name : '${parent}__$name';''',
          r'''  String get path {
    if (parent.isEmpty || parent == _rootKey) return name;
    return '${parent}__$name';
  }''');
    }
    target.writeAsStringSync(source);
  }
  final manager = file('lib/dependency_manager.dart');
  manager.writeAsStringSync(
      replaceOnce(manager.readAsStringSync(), '''      for (final dep in deps) {
        if (!prevDeps.contains(dep)) {
          _addDependent(dep, doc);
        }
      }
      for (final dep in prevDeps) {
        if (!deps.contains(dep)) {
          _removeDependent(dep, doc);
        }
      }''', '''      for (final dep in deps.difference(prevDeps)) {
        _addDependent(dep, doc);
      }
      for (final dep in prevDeps.difference(deps)) {
        _removeDependent(dep, doc);
      }'''));
}

/// Restores the path-map + Document.fromPath deletion model, leaving all other
/// fixes in place, including snapshots of caller-owned dependency sets.
void _rebuildDocumentsFromPaths(File manager) {
  var source = manager.readAsStringSync();
  final start = source.indexOf('/// Keeps the dependent handle');
  final end = source.indexOf('class DependencyManager {');
  if (start < 0 || end < start) throw StateError('Update entry transform');
  source = source.replaceRange(start, end, '');
  source = replaceOnce(
      source, 'ValueStore<_DependencyEntry>()', 'ValueStore<Set<Document>>()');
  const lookup = '_dependencies.get(doc.path)?.dependencies';
  const write = '_DependencyEntry(doc, deps)';
  if (lookup.allMatches(source).length != 2 ||
      write.allMatches(source).length != 2) {
    throw StateError('Update dependency entry uses');
  }
  source = source
      .replaceAll(lookup, '_dependencies.get(doc.path)')
      .replaceAll(write, 'deps');
  final from =
      source.indexOf('    final entries = _dependencies.extractValues(path);');
  final to = source.indexOf('\n  }\n\n  void deleteDocument', from);
  if (from < 0 || to < 0) {
    throw StateError('Update document deletion transform');
  }
  var body = replaceOnce(source.substring(from, to),
      '_dependencies.extractValues(path)', '_dependencies.extract(path)');
  body = replaceOnce(body, '    for (final entry in entries) {',
      '''    for (final entry in entries.entries) {
      final dependent = Document.fromPath(entry.key);''');
  body = replaceOnce(body, 'entry.dependencies', 'entry.value');
  body = replaceOnce(body, 'entry.doc', 'dependent');
  source = source.replaceRange(from, to, body);
  manager.writeAsStringSync(source);
}
