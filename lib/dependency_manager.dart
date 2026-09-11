part of 'loon.dart';

class DependencyManager {
  /// The index of dependencies of a document by path.
  final _dependencies = ValueStore<Set<Document>>();

  /// The reverse index of dependents of a document by path.
  final _dependents = ValueStore<Set<Document>>();

  void _addDependent(Document dep, Document doc) {
    final dependents =
        _dependents.get(dep.path) ?? _dependents.write(dep.path, <Document>{});
    dependents.add(doc);
  }

  void _removeDependent(Document dep, Document doc) {
    final dependents = _dependents.get(dep.path);
    if (dependents == null) {
      return;
    }

    if (dependents.length == 1) {
      _dependents.delete(dep.path, recursive: false);
    } else {
      dependents.remove(doc);
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

    final deps = dependenciesBuilder.call(snap);
    final prevDeps = _dependencies.get(doc.path);

    if (setEquals(deps, prevDeps)) {
      return;
    }

    if (deps != null && prevDeps != null) {
      for (final dep in deps.difference(prevDeps)) {
        _addDependent(dep, doc);
      }
      for (final dep in prevDeps.difference(deps)) {
        _removeDependent(dep, doc);
      }

      if (deps.isEmpty) {
        // Only the document's own dependencies are removed; the documents of its
        // subcollections keep theirs.
        _dependencies.delete(doc.path, recursive: false);
      } else {
        _dependencies.write(doc.path, deps);
      }
    } else if (deps != null) {
      for (final dep in deps) {
        _addDependent(dep, doc);
      }

      _dependencies.write(doc.path, deps);
    } else if (prevDeps != null) {
      for (final dep in prevDeps) {
        _removeDependent(dep, doc);
      }

      _dependencies.delete(doc.path, recursive: false);
    }
  }

  Set<Document>? getDependencies(Document doc) {
    return _dependencies.get(doc.path);
  }

  /// Returns the dependents of the given document.
  Set<Document>? getDependents(
    StoreReference ref, {
    bool recursive = false,
  }) {
    return recursive
        ? _dependents.extractValues(ref.path).flatten()
        : _dependents.get(ref.path);
  }

  /// Deleting a ref in the dependency store performs two operations:
  ///
  /// 1. It deletes all dependency entries under the given path.
  /// 2. It deletes all dependent entries that contain deleted documents.
  void _deleteRef(StoreReference ref) {
    final StoreReference(:path) = ref;

    final extractedDeps = _dependencies.extractValues(path).flatten();
    _dependencies.delete(path);

    for (final dep in extractedDeps) {
      final dependents = getDependents(dep);
      if (dependents != null) {
        dependents.removeWhere((dependent) => dependent.isDescendant(ref));
        if (dependents.isEmpty) {
          _dependents.delete(dep.path, recursive: false);
        }
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
    return {
      "dependencyStore": _dependencies.inspect(),
      "dependentsStore": _dependents.inspect(),
    };
  }
}
