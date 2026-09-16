import 'dart:io';
import 'package:path/path.dart' as p;
import 'tool_support.dart';

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
];

/// Fail-closed transforms applied only to disposable copies of the library.
void configureVariant(String destination, String variant) {
  if (!variantNames.contains(variant)) throw ArgumentError.value(variant);
  File file(String path) => File(p.join(destination, path));
  if (['document_before', 'document_before_paths'].contains(variant)) {
    _beforeDocumentChanges(file);
  }
  if (['document_paths', 'document_before_paths'].contains(variant)) {
    _rebuildDocumentsFromPaths(file('lib/dependency_manager.dart'));
  }
  if (['baseline', 'identity'].contains(variant)) {
    final base = file('lib/store/base_value_store.dart');
    var source = base.readAsStringSync();
    final start = source.indexOf('  T? get(String path) {');
    final end = source.indexOf('\n  /// Returns a map of all values', start);
    if (start < 0 || end < 0) throw StateError('Update get transform');
    source = source.replaceRange(start, end, '''  T? get(String path) {
    final segments = _getSegments(path);
    final last = segments.removeLast();
    return _getNode(_store, segments)?[_values]?[last];
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
    var source = replaceOnce(
        target.readAsStringSync(),
        '''        if (!eventStore.hasValue(doc.path)) {
          writeDocument(doc, BroadcastEvents.touched);
        }''',
        '        _touchDependent(doc);');
    source = replaceOnce(source, '  void _deleteRef(StoreReference ref) {',
        '''  void _touchDependent(Document doc) {
    final path = doc.path;
    if (eventStore.hasValue(path)) return;
    observerValueStore.delete(path, recursive: false);
    observerValueStore.delete(doc.parent, recursive: false);
    eventStore.write(path, BroadcastEvents.touched);
    _broadcastDependents(doc);
  }

  void _deleteRef(StoreReference ref) {''');
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
    manager.writeAsStringSync(text.replaceRange(
        from, to, '''    _dependencies.forEachValueUnder(path, (entry) {
      for (final dependency in entry.dependencies) {
        _removeDependent(dependency, entry.doc);
      }
    });
    _dependencies.delete(path);'''));
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
  source = replaceOnce(
      source, '''    final entries = _dependencies.extractValues(path);
    _dependencies.delete(path);

    for (final entry in entries) {
      for (final dependency in entry.dependencies) {
        _removeDependent(dependency, entry.doc);
      }
    }''', '''    final extracted = _dependencies.extract(path);
    _dependencies.delete(path);

    for (final MapEntry(key: docPath, value: dependencies) in extracted.entries) {
      final dependent = Document.fromPath(docPath);
      for (final dependency in dependencies) {
        _removeDependent(dependency, dependent);
      }
    }''');
  manager.writeAsStringSync(source);
}
