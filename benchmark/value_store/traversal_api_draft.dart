import 'dart:collection';
import 'package:loon/loon.dart';

/// Shared prefix lookup for new prototypes. A selected path's own value lives
/// in its parent's value bucket, separately from the descendant node.
({Map? node, bool hasOwn, T? own}) locateSubtree<T>(
    ValueStore<T> store, String path) {
  if (path.isEmpty) {
    return (node: store.inspect(), hasOwn: false, own: null);
  }
  final segments = path.split('__');
  final last = segments.removeLast();
  Map? parent = store.inspect();
  for (final segment in segments) {
    parent = parent?[segment] as Map?;
    if (parent == null) return (node: null, hasOwn: false, own: null);
  }
  final Map<String, T>? values = parent?['__values'];
  final hasOwn = values?.containsKey(last) ?? false;
  return (
    node: parent?[last] as Map?,
    hasOwn: hasOwn,
    own: hasOwn ? values![last] : null
  );
}

/// A live, restartable Iterable with an explicit DFS stack instead of sync*.
/// Structural mutation during iteration is unsupported, as with the other
/// proposals. Prefix resolution is deferred until the first moveNext call.
Iterable<T> manualValuesUnder<T>(ValueStore<T> store, String path) =>
    _SubtreeIterable(store, path);

class _SubtreeIterable<T> extends IterableBase<T> {
  final ValueStore<T> store;
  final String path;
  _SubtreeIterable(this.store, this.path);

  @override
  Iterator<T> get iterator => _SubtreeIterator(store, path);
}

class _SubtreeIterator<T> implements Iterator<T> {
  final ValueStore<T> store;
  final String path;
  final _ancestors = <Iterator<MapEntry<dynamic, dynamic>>>[];
  Iterator<T>? _bucket;
  T? _current;
  bool _started = false;
  bool _done = false;

  _SubtreeIterator(this.store, this.path);

  // current is unspecified before the first successful moveNext and after
  // exhaustion. The nullable storage also handles actual null values when T
  // is nullable, without using null as an end-of-sequence sentinel.
  @override
  T get current => _current as T;

  void _enter(Map? node) {
    if (node == null) return;
    final Map<String, T>? values = node['__values'];
    _bucket = values?.values.iterator;
    if (node.length > (values == null ? 0 : 1)) {
      _ancestors.add(node.entries.iterator);
    }
  }

  @override
  bool moveNext() {
    if (_done) return false;
    if (!_started) {
      _started = true;
      final scope = locateSubtree(store, path);
      _enter(scope.node);
      if (scope.hasOwn) {
        _current = scope.own;
        return true;
      }
    }
    while (true) {
      final bucket = _bucket;
      if (bucket != null && bucket.moveNext()) {
        _current = bucket.current;
        return true;
      }
      _bucket = null;
      var enteredChild = false;
      while (_ancestors.isNotEmpty) {
        final children = _ancestors.last;
        if (!children.moveNext()) {
          _ancestors.removeLast();
          continue;
        }
        final child = children.current;
        if (child.key == '__values') continue;
        _enter(child.value as Map?);
        enteredChild = true;
        break;
      }
      if (!enteredChild) {
        _done = true;
        _current = null;
        return false;
      }
    }
  }
}

/// Control with typed value buckets and leaf skipping, matching the specialized
/// walkers' tree navigation. Keeps a generic per-value consumer callback.
void visitTypedValues<T>(
    ValueStore<T> store, String path, void Function(T) visit) {
  final scope = locateSubtree(store, path);
  if (scope.hasOwn) visit(scope.own as T);
  _visitNode(scope.node, visit);
}

void _visitNode<T>(Map? node, void Function(T) visit) {
  if (node == null) return;
  final Map<String, T>? values = node['__values'];
  if (values != null) {
    for (final value in values.values) {
      visit(value);
    }
    if (node.length == 1) return;
  }
  for (final entry in node.entries) {
    if (entry.key != '__values') _visitNode(entry.value as Map?, visit);
  }
}

/// Concrete operation inside the walker: no arbitrary per-value callback.
int sumSpecialized(ValueStore<int> store, String path) {
  final scope = locateSubtree(store, path);
  return (scope.hasOwn ? scope.own! : 0) + _sumNode(scope.node);
}

int _sumNode(Map? node) {
  if (node == null) return 0;
  var total = 0;
  final Map<String, int>? values = node['__values'];
  if (values != null) {
    for (final value in values.values) {
      total += value;
    }
    if (node.length == 1) return total;
  }
  for (final entry in node.entries) {
    if (entry.key != '__values') total += _sumNode(entry.value as Map?);
  }
  return total;
}

List<T> exportSpecialized<T>(ValueStore<T> store, String path) {
  final scope = locateSubtree(store, path);
  final result = <T>[];
  if (scope.hasOwn) result.add(scope.own as T);
  _exportNode(scope.node, result);
  return result;
}

void _exportNode<T>(Map? node, List<T> result) {
  if (node == null) return;
  final Map<String, T>? values = node['__values'];
  if (values != null) {
    result.addAll(values.values);
    if (node.length == 1) return;
  }
  for (final entry in node.entries) {
    if (entry.key != '__values') _exportNode(entry.value as Map?, result);
  }
}

class TraversalEntry {
  final Document doc;
  final Set<Document> dependencies;
  TraversalEntry(this.doc, this.dependencies);
}

/// All cleanup candidates use exactly this operation, called directly from
/// their loop or through their generic callback as appropriate.
void removeTraversalEntry(
    TraversalEntry entry, ValueStore<Set<Document>> reverse) {
  for (final dependency in entry.dependencies) {
    final existing = reverse.get(dependency.path);
    if (existing == null) continue;
    existing.remove(entry.doc);
    if (existing.isEmpty) reverse.delete(dependency.path, recursive: false);
  }
}

void cleanupSpecialized(ValueStore<TraversalEntry> forward, String path,
    ValueStore<Set<Document>> reverse) {
  final scope = locateSubtree(forward, path);
  if (scope.hasOwn) removeTraversalEntry(scope.own!, reverse);
  _cleanupNode(scope.node, reverse);
}

void _cleanupNode(Map? node, ValueStore<Set<Document>> reverse) {
  if (node == null) return;
  final Map<String, TraversalEntry>? values = node['__values'];
  if (values != null) {
    for (final entry in values.values) {
      removeTraversalEntry(entry, reverse);
    }
    if (node.length == 1) return;
  }
  for (final entry in node.entries) {
    if (entry.key != '__values') _cleanupNode(entry.value as Map?, reverse);
  }
}

Set<Document> unionSpecialized(ValueStore<Set<Document>> store, String path) {
  final scope = locateSubtree(store, path);
  final result = <Document>{};
  if (scope.hasOwn) result.addAll(scope.own!);
  _unionNode(scope.node, result);
  return result;
}

void _unionNode(Map? node, Set<Document> result) {
  if (node == null) return;
  final Map<String, Set<Document>>? values = node['__values'];
  if (values != null) {
    for (final group in values.values) {
      result.addAll(group);
    }
    if (node.length == 1) return;
  }
  for (final entry in node.entries) {
    if (entry.key != '__values') _unionNode(entry.value as Map?, result);
  }
}
