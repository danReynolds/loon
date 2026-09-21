import 'dart:io';
import 'tool_support.dart';

/// Experimental transforms; no references survive the synchronous operation.
void configureScopedTraversal(File Function(String) file, String variant) {
  if (variant == 'scoped_collections_recent') {
    configureScopedTraversal(file, 'scoped_collections');
    final manager = file('lib/dependency_manager.dart');
    var text = manager.readAsStringSync();
    text = text.replaceRange(text.indexOf('  void _removeDependent('),
        text.indexOf('  /// Updates the dependencies/'), cleanRemoveDependent);
    text = text.replaceRange(text.indexOf('  void _deleteRef('),
        text.indexOf('  void deleteDocument('), cleanDeleteRef);
    manager.writeAsStringSync(text);
    return;
  }
  if (variant == 'scoped_collections') {
    configureScopedTraversal(file, 'scoped_cursor_cleanup');
    final draft = file('benchmark/value_store/collection_values_draft.dart')
        .readAsStringSync()
        .replaceFirst(
            "import 'package:loon/loon.dart';", "part of '../loon.dart';")
        .replaceAll('CollectionValues', '_CollectionValues')
        .replaceAll('canUseDocumentCollection', '_canUseDocumentCollection');
    file('lib/store/document_values.dart').writeAsStringSync(draft);
    final broadcast = file('lib/broadcast_manager.dart');
    var text = broadcast.readAsStringSync();
    text = text.replaceRange(text.indexOf('  void _queueDependentEvents('),
        text.indexOf('  void _deleteRef('), collectionBroadcast);
    broadcast.writeAsStringSync(text);
    final manager = file('lib/dependency_manager.dart');
    text = manager.readAsStringSync();
    text = text.replaceRange(
        text.indexOf('  void _removeDependent('),
        text.indexOf('  /// Updates the dependencies/'),
        collectionRemoveDependent);
    text = text.replaceAll(
        '_DocumentValues(_dependents)', '_CollectionValues(_dependents)');
    manager.writeAsStringSync(text);
    return;
  }
  if (['scoped_cursor', 'scoped_cursor_simple', 'scoped_cursor_cleanup']
      .contains(variant)) {
    final draft = file('benchmark/value_store/document_values_draft.dart')
        .readAsStringSync()
        .replaceFirst(
            '// Copied into the library only in disposable profiling variants.\n', '')
        .replaceFirst(
            "import 'package:loon/loon.dart';", "part of '../loon.dart';")
        .replaceAll('DocumentValues', '_DocumentValues');
    file('lib/store/document_values.dart').writeAsStringSync(draft);
    final library = file('lib/loon.dart');
    if (!library
        .readAsStringSync()
        .contains("part 'store/document_values.dart';")) {
      library.writeAsStringSync(replaceOnce(
          library.readAsStringSync(),
          "part 'store/value_store.dart';",
          "part 'store/value_store.dart';\npart 'store/document_values.dart';"));
    }
    final broadcast = file('lib/broadcast_manager.dart');
    final source = broadcast.readAsStringSync();
    final start = source.indexOf('  void _queueDependentEvents(');
    final end = source.indexOf('  void _deleteRef(', start);
    if (start < 0 || end < 0) throw StateError('Update cursor transform');
    broadcast
        .writeAsStringSync(source.replaceRange(start, end, cursorBroadcast));
    if (variant == 'scoped_cursor') {
      // Restore the previous last-set cleanup even when the supplied library
      // already uses the shared cursor for deletion.
      configureScopedTraversal(file, 'scoped_guard');
      final text = broadcast.readAsStringSync();
      broadcast.writeAsStringSync(text.replaceRange(
          text.indexOf('  void _queueDependentEvents('),
          text.indexOf('  void _deleteRef('),
          cursorBroadcast));
    } else {
      final manager = file('lib/dependency_manager.dart');
      var text = manager.readAsStringSync();
      final from = RegExp(r'  (?:void|Set<Document>\?) _removeDependent\(')
              .firstMatch(text)
              ?.start ??
          -1;
      final to = text.indexOf('  /// Updates the dependencies/', from);
      if (from < 0 || to < 0) {
        throw StateError('Update simple removal transform');
      }
      text = text.replaceRange(
          from,
          to,
          variant == 'scoped_cursor_simple'
              ? simpleRemoveDependent
              : cursorRemoveDependent);
      const deleteLine = '    _dependencies.delete(path);\n';
      final deleteIndex =
          text.indexOf(deleteLine, text.indexOf('  void _deleteRef('));
      final loopStart = deleteIndex < 0 ? -1 : deleteIndex + deleteLine.length;
      final loopEnd = text.indexOf('\n  }\n\n  void deleteDocument', loopStart);
      if (loopStart < 0 || loopEnd < 0) {
        throw StateError('Update simple cleanup transform');
      }
      final loop = variant == 'scoped_cursor_simple'
          ? '''    for (final entry in entries) {
      for (final dependency in entry.dependencies) {
        _removeDependent(dependency, entry.doc);
      }
    }'''
          : '''    final values = _DocumentValues(_dependents);
    for (final entry in entries) {
      for (final dependency in entry.dependencies) {
        _removeDependent(dependency, entry.doc, values: values);
      }
    }''';
      manager
          .writeAsStringSync(text.replaceRange(loopStart, loopEnd, '\n$loop'));
    }
    return;
  }
  if (variant == 'delete_recent') {
    final target = file('lib/dependency_manager.dart');
    // The working library may already contain the selected form of this idea.
    if (target
        .readAsStringSync()
        .contains('Set<Document>? previousDependents;')) {
      return;
    }
    // First restore the simple loop if the supplied library uses a cursor.
    if (RegExp(r'final values = _(Document|Collection)Values\(_dependents\);')
        .hasMatch(target.readAsStringSync())) {
      var text = target.readAsStringSync();
      final from = text.indexOf('  void _removeDependent(');
      final to = text.indexOf('  /// Updates the dependencies/', from);
      if (from < 0 || to < 0) {
        throw StateError('Update recent removal transform');
      }
      text = text.replaceRange(from, to, simpleRemoveDependent);
      text = text.replaceFirst(
          RegExp(
              r'    final values = _(Document|Collection)Values\(_dependents\);\n'),
          '');
      text = replaceOnce(
          text,
          '_removeDependent(dependency, entry.doc, values: values);',
          '_removeDependent(dependency, entry.doc);');
      target.writeAsStringSync(text);
    }
    target.writeAsStringSync(replaceOnce(
        target.readAsStringSync(), '''    for (final entry in entries) {
      for (final dependency in entry.dependencies) {
        _removeDependent(dependency, entry.doc);
      }
    }''', '''    String? previousPath;
    Set<Document>? previousDependents;
    for (final entry in entries) {
      for (final dependency in entry.dependencies) {
        final path = dependency.path;
        if (path != previousPath) {
          previousPath = path;
          previousDependents = _dependents.get(path);
        }
        final dependents = previousDependents;
        if (dependents == null) continue;
        dependents.remove(entry.doc);
        if (dependents.isEmpty) {
          _dependents.delete(path, recursive: false);
          previousPath = null;
          previousDependents = null;
        }
      }
    }'''));
  }
  if (['batch_buckets', 'batch_clean', 'scoped_clean', 'scoped_guard']
      .contains(variant)) {
    final target = file('lib/broadcast_manager.dart');
    final source = target.readAsStringSync();
    final start = source.indexOf('  void _broadcastDependents(');
    final end = source.indexOf('  void _deleteRef(', start);
    if (start < 0 || end < 0) throw StateError('Update propagation transform');
    var body = variant == 'batch_buckets' ? scopedBroadcast : cleanBroadcast;
    if (variant == 'scoped_guard') {
      body = replaceOnce(
          body, '''    final manager = Loon._instance.dependencyManager;
    final dependents = manager.getDependents(ref, recursive: recursive);
    if (dependents == null || dependents.isEmpty) return;

''', '''    final dependents = Loon._instance.dependencyManager
        .getDependents(ref, recursive: recursive);
    if (dependents == null || dependents.isEmpty) return;
    _queueDependentEvents(dependents);
  }

  void _queueDependentEvents(Set<Document> dependents) {
    final manager = Loon._instance.dependencyManager;

''');
    }
    target.writeAsStringSync(source.replaceRange(start, end, body));
  }
  if (variant == 'scoped_clean' || variant == 'scoped_guard') {
    final target = file('lib/dependency_manager.dart');
    var source = target.readAsStringSync();
    var start = source.indexOf('  void _removeDependent(');
    if (start < 0) start = source.indexOf('  Set<Document>? _removeDependent(');
    var end = source.indexOf('  /// Updates the dependencies/', start);
    if (start < 0 || end < 0) throw StateError('Update removal transform');
    source = source.replaceRange(start, end, cleanRemoveDependent);
    start = source.indexOf('  void _deleteRef(');
    end = source.indexOf('  void deleteDocument(', start);
    if (start < 0 || end < 0) throw StateError('Update deletion transform');
    target.writeAsStringSync(source.replaceRange(start, end, cleanDeleteRef));
  }
}

const cursorBroadcast =
    '''  void _queueDependentEvents(Set<Document> dependents) {
    final manager = Loon._instance.dependencyManager;
    final events = _DocumentValues(eventStore);
    final reverse = _DocumentValues(manager._dependents);

    void visit(Set<Document> dependents) {
      for (final doc in dependents) {
        if (events.get(doc) != null) continue;

        observerValueStore.delete(doc.path, recursive: false);
        observerValueStore.delete(doc.parent, recursive: false);
        events.write(doc, BroadcastEvents.touched);

        final next = reverse.get(doc);
        if (next != null) visit(next);
      }
    }

    visit(dependents);
  }

''';

const simpleRemoveDependent =
    '''  void _removeDependent(Document dependency, Document dependent) {
    final dependents = _dependents.get(dependency.path);
    if (dependents == null) return;

    dependents.remove(dependent);
    if (dependents.isEmpty) {
      _dependents.delete(dependency.path, recursive: false);
    }
  }

''';

const cursorRemoveDependent = '''  void _removeDependent(
    Document dependency,
    Document dependent, {
    _DocumentValues<Set<Document>>? values,
  }) {
    final dependents = values == null
        ? _dependents.get(dependency.path)
        : values.get(dependency);
    if (dependents == null) return;

    dependents.remove(dependent);
    if (dependents.isEmpty) {
      _dependents.delete(dependency.path, recursive: false);
      values?.invalidate();
    }
  }

''';

const collectionBroadcast =
    '''  void _queueDependentEvents(Set<Document> dependents) {
    final manager = Loon._instance.dependencyManager;
    final eventCollections = _CollectionValues(eventStore);
    final reverseCollections = _CollectionValues(manager._dependents);

    void visit(Set<Document> dependents) {
      for (final doc in dependents) {
        final useCollection = _canUseDocumentCollection(doc);
        final events = useCollection ? eventCollections[doc.parent] : null;
        final pending = useCollection ? (events?[doc.id]) : eventStore.get(doc.path);
        if (pending != null) continue;

        observerValueStore.delete(doc.path, recursive: false);
        observerValueStore.delete(doc.parent, recursive: false);
        if (events != null) {
          events[doc.id] = BroadcastEvents.touched;
        } else {
          eventStore.write(doc.path, BroadcastEvents.touched);
          eventCollections.invalidate();
        }

        final next = useCollection
            ? (reverseCollections[doc.parent]?[doc.id])
            : manager.getDependents(doc);
        if (next != null) visit(next);
      }
    }

    visit(dependents);
  }

''';

const collectionRemoveDependent = '''  void _removeDependent(
    Document dependency,
    Document dependent, {
    _CollectionValues<Set<Document>>? values,
  }) {
    final dependents = values != null && _canUseDocumentCollection(dependency)
        ? (values[dependency.parent]?[dependency.id])
        : _dependents.get(dependency.path);
    if (dependents == null) return;

    dependents.remove(dependent);
    if (dependents.isEmpty) {
      _dependents.delete(dependency.path, recursive: false);
      values?.invalidate();
    }
  }

''';

// At most one event bucket and one reverse bucket per traversal. No map of
// all encountered collections, persistent index or deletion invalidation hook.
const scopedBroadcast = '''  void _broadcastDependents(
    StoreReference ref, {
    bool recursive = false,
  }) {
    final manager = Loon._instance.dependencyManager;
    String? eventParent;
    Map<String, BroadcastEvents>? events;
    String? reverseParent;
    Map<String, Set<Document>>? reverse;

    // Constructors also allow unusual paths. Their concatenation may not have
    // the same segment boundary as parent/id, so retain normal path semantics.
    bool canUseBucket(Document doc) => doc.id.isNotEmpty &&
        !doc.id.contains('__') && !doc.parent.endsWith('_');

    Set<Document>? dependentsOf(Document doc) {
      if (!canUseBucket(doc)) return manager.getDependents(doc);
      if (reverseParent != doc.parent) {
        reverseParent = doc.parent;
        reverse = manager._dependents.getChildValues(doc.parent);
      }
      return reverse?[doc.id];
    }

    void visit(Set<Document>? dependents) {
      if (dependents == null) return;
      for (final doc in dependents) {
        final useBucket = canUseBucket(doc);
        if (useBucket && eventParent != doc.parent) {
          eventParent = doc.parent;
          events = eventStore.getChildValues(doc.parent);
        }
        final pending = useBucket ? (events?[doc.id]) : eventStore.get(doc.path);
        if (pending != null) continue;
        observerValueStore.delete(doc.path, recursive: false);
        observerValueStore.delete(doc.parent, recursive: false);
        if (useBucket && events != null) {
          events![doc.id] = BroadcastEvents.touched;
        } else {
          eventStore.write(doc.path, BroadcastEvents.touched);
          if (useBucket) events = eventStore.getChildValues(doc.parent);
          // An unusual path can create a bucket previously cached as absent.
          else eventParent = null;
        }
        visit(dependentsOf(doc));
      }
    }

    visit(manager.getDependents(ref, recursive: recursive));
  }

''';

const cleanBroadcast = '''  void _broadcastDependents(
    StoreReference ref, {
    bool recursive = false,
  }) {
    final manager = Loon._instance.dependencyManager;
    final dependents = manager.getDependents(ref, recursive: recursive);
    if (dependents == null || dependents.isEmpty) return;

    // This synchronous walk only adds events and reads the reverse index. Keep
    // at most one collection map from each store, only until the walk returns.
    String? eventParent;
    Map<String, BroadcastEvents>? events;
    String? reverseParent;
    Map<String, Set<Document>>? reverse;

    void visit(Set<Document> dependents) {
      for (final doc in dependents) {
        // Unusual constructor inputs can split differently from parent/id.
        final useBucket = doc.id.isNotEmpty &&
            !doc.id.contains('__') && !doc.parent.endsWith('_');
        if (useBucket && eventParent != doc.parent) {
          eventParent = doc.parent;
          events = eventStore.getChildValues(doc.parent);
        }
        final pending = useBucket ? (events?[doc.id]) : eventStore.get(doc.path);
        if (pending != null) continue;

        observerValueStore.delete(doc.path, recursive: false);
        observerValueStore.delete(doc.parent, recursive: false);
        if (useBucket && events != null) {
          events![doc.id] = BroadcastEvents.touched;
        } else {
          eventStore.write(doc.path, BroadcastEvents.touched);
          if (useBucket) {
            events = eventStore.getChildValues(doc.parent);
          } else {
            // This write may have created a bucket previously cached as absent.
            eventParent = null;
          }
        }

        Set<Document>? next;
        if (useBucket) {
          if (reverseParent != doc.parent) {
            reverseParent = doc.parent;
            reverse = manager._dependents.getChildValues(doc.parent);
          }
          next = reverse?[doc.id];
        } else {
          next = manager.getDependents(doc);
        }
        if (next != null) visit(next);
      }
    }

    visit(dependents);
  }

''';

const cleanRemoveDependent = '''  Set<Document>? _removeDependent(
    Document dependency,
    Document dependent, {
    Set<Document>? dependents,
  }) {
    dependents ??= _dependents.get(dependency.path);
    if (dependents == null) return null;

    dependents.remove(dependent);
    if (dependents.isEmpty) {
      _dependents.delete(dependency.path, recursive: false);
      return null;
    }
    return dependents;
  }

''';

const cleanDeleteRef = '''  void _deleteRef(StoreReference ref) {
    final StoreReference(:path) = ref;

    final entries = _dependencies.extractValues(path);
    _dependencies.delete(path);

    // Reuse a shared dependency's set only within this removal operation.
    String? previousPath;
    Set<Document>? previousDependents;
    for (final entry in entries) {
      for (final dependency in entry.dependencies) {
        final path = dependency.path;
        previousDependents = _removeDependent(dependency, entry.doc,
            dependents: path == previousPath ? previousDependents : null);
        previousPath = path;
      }
    }
  }

''';
