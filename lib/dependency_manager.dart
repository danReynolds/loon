part of 'loon.dart';

/// Keeps the dependent handle available when its dependency entries are deleted.
class _DependencyEntry {
  final Document doc;
  final Set<Document> dependencies;

  _DependencyEntry(this.doc, this.dependencies);

  Json toJson() => {
        'doc': doc.path,
        'dependencies': [
          for (final dependency in dependencies) dependency.path
        ],
      };
}

class DependencyManager {
  /// The index of dependencies of a document by path.
  final _dependencies = ValueStore<_DependencyEntry>();

  /// The reverse index of dependents of a document by path.
  final _dependents = ValueStore<Set<Document>>();

  void _addDependent(Document dependency, Document dependent) {
    final dependents = _dependents.get(dependency.path) ??
        _dependents.write(dependency.path, {});
    dependents.add(dependent);
  }

  Set<Document>? _removeDependent(
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

    if (deps != null) {
      for (final dep in deps) {
        if (prevDeps?.contains(dep) != true) {
          _addDependent(dep, doc);
        }
      }
    }
    if (prevDeps != null) {
      for (final dep in prevDeps) {
        if (deps?.contains(dep) != true) {
          _removeDependent(dep, doc);
        }
      }
    }

    if (deps == null || (prevDeps != null && deps.isEmpty)) {
      // Preserve an initial empty result, but remove entries whose dependencies
      // were cleared. Subcollections keep their own dependency entries.
      _dependencies.delete(doc.path, recursive: false);
    } else {
      _dependencies.write(doc.path, _DependencyEntry(doc, deps));
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
  /// 2. It removes the deleted documents from their dependencies' reverse indexes.
  ///
  /// Surviving documents that depend on the deleted path keep their memberships,
  /// so they can react to both its deletion and later recreation.
  void _deleteRef(StoreReference ref) {
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
