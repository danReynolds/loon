part of 'loon.dart';

/// Keeps the dependent handle available when its dependency entries are deleted.
class _DependencyEntry {
  final Document doc;
  final Set<Document> dependencies;

  _DependencyEntry(this.doc, this.dependencies);
}

class DependencyManager {
  /// The index of dependencies of a document by path.
  final _dependencies = ValueStore<_DependencyEntry>();

  /// The reverse index of dependents of a document by path.
  final _dependents = ValueStore<Set<Document>>();

  void _addDependent(Document doc, Document dep) {
    final dependents =
        _dependents.get(doc.path) ?? _dependents.write(doc.path, {});
    dependents.add(dep);
  }

  void _removeDependent(Document doc, Document dep) {
    final dependents = _dependents.get(doc.path);
    if (dependents == null) {
      return;
    }

    dependents.remove(dep);
    if (dependents.isEmpty) {
      _dependents.delete(doc.path, recursive: false);
    }
  }

  /// Updates the dependencies/dependents store for the given [DocumentSnapshot]
  /// with the document's recalculated dependencies.
  void updateDependencies<T>(DocumentSnapshot<T> snap) {
    final doc = snap.doc;
    final dependenciesBuilder = doc.dependenciesBuilder;

    if (dependenciesBuilder == null) {
      return;
    }

    // Keep the previous dependencies independent of a mutable set owned by the builder.
    final deps = dependenciesBuilder.call(snap)?.toSet();
    final prevDeps = _dependencies.get(doc.path)?.dependencies;

    if (setEquals(deps, prevDeps)) {
      return;
    }

    if (deps != null && prevDeps != null) {
      for (final dep in deps) {
        if (!prevDeps.contains(dep)) {
          _addDependent(dep, doc);
        }
      }
      for (final dep in prevDeps) {
        if (!deps.contains(dep)) {
          _removeDependent(dep, doc);
        }
      }

      if (deps.isEmpty) {
        // Only the document's own dependencies are removed; the documents of its
        // subcollections keep theirs.
        _dependencies.delete(doc.path, recursive: false);
      } else {
        _dependencies.write(doc.path, _DependencyEntry(doc, deps));
      }
    } else if (deps != null) {
      for (final dep in deps) {
        _addDependent(dep, doc);
      }

      _dependencies.write(doc.path, _DependencyEntry(doc, deps));
    } else if (prevDeps != null) {
      for (final dep in prevDeps) {
        _removeDependent(dep, doc);
      }

      _dependencies.delete(doc.path, recursive: false);
    }
  }

  /// Returns all dependencies of the given document.
  Set<Document>? getDependencies(Document doc) {
    return _dependencies.get(doc.path)?.dependencies;
  }

  /// Returns all dependents under the given store reference.
  Set<Document>? getDependents(
    StoreReference ref, {
    bool recursive = false,
  }) {
    return recursive
        ? _dependents.extractValues(ref.path).flatten()
        : _dependents.get(ref.path);
  }

  /// Deleting a store ref performs two operations:
  ///
  /// 1. It deletes all dependency entries under the given path.
  /// 2. It deletes all dependent entries for the deleted documents.
  void _deleteRef(StoreReference ref) {
    final StoreReference(:path) = ref;

    final entries = _dependencies.extractValues(path);
    _dependencies.delete(path);

    for (final entry in entries) {
      for (final dependency in entry.dependencies) {
        _removeDependent(dependency, entry.doc);
      }
    }
  }

  void deleteDocument(Document doc) {
    _deleteRef(doc);
  }

  void deleteCollection(Collection collection) {
    _deleteRef(collection);
  }

  /// Clears all dependencies and dependents of documents.
  void clear() {
    _dependencies.clear();
    _dependents.clear();
  }

  Map inspect() {
    // Preserve the set-valued inspection format while entries retain their documents.
    Map inspectDependencies(Map node) => node.map(
          (key, value) => MapEntry(
            key,
            value is _DependencyEntry
                ? value.dependencies
                : inspectDependencies(value as Map),
          ),
        );

    return {
      "dependencyStore": inspectDependencies(_dependencies.inspect()),
      "dependentsStore": _dependents.inspect(),
    };
  }
}
