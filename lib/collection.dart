part of loon;

class Collection<T> extends StoreNode {
  final FromJson<T>? fromJson;
  final ToJson<T>? toJson;
  final PersistorSettings? persistorSettings;

  /// Returns the set of documents that the document associated with the given
  /// [DocumentSnapshot] is dependent on.
  final DependenciesBuilder<T>? dependenciesBuilder;

  Collection(
    super.name, {
    super.parent,
    super.children,
    this.fromJson,
    this.toJson,
    this.persistorSettings,
    this.dependenciesBuilder,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is Collection) {
      return other.path == path;
    }
    return false;
  }

  @override
  int get hashCode => Object.hashAll([parent?.path, name]);

  bool isPersistenceEnabled() {
    return persistorSettings?.persistenceEnabled ??
        Loon._instance._isGlobalPersistenceEnabled;
  }

  bool exists() {
    return children?.isNotEmpty ?? false;
  }

  Document<T> doc(String id) {
    final childNode = children?[id];
    if (childNode is Document<T>) {
      return childNode;
    }

    return Document<T>(
      id,
      parent: this,
      children: childNode?.children,
      fromJson: fromJson,
      toJson: toJson,
      persistorSettings: persistorSettings,
      dependenciesBuilder: dependenciesBuilder,
    );
  }

  void delete({
    bool broadcast = true,
  }) {
    // Loon._instance._deleteCollection(
    //   key,
    //   broadcast: broadcast,
    //   persist: isPersistenceEnabled(),
    // );
  }

  void replace(
    List<DocumentSnapshot<T>> snaps, {
    bool broadcast = true,
  }) {
    // Loon._instance._replaceCollection<T>(
    //   key,
    //   snaps: snaps,
    //   fromJson: fromJson,
    //   toJson: toJson,
    //   persistorSettings: persistorSettings,
    //   dependenciesBuilder: dependenciesBuilder,
    //   broadcast: broadcast,
    // );
  }

  List<DocumentSnapshot<T>> get() {
    return children?.values
            .map((child) => this.doc(child.name).get()!)
            .toList() ??
        [];
  }

  Stream<List<DocumentSnapshot<T>>> stream() {
    return Query<T>(this).observe().stream();
  }

  Stream<List<DocumentChangeSnapshot<T>>> streamChanges() {
    return Query<T>(this).observe().streamChanges();
  }

  Query<T> where(FilterFn<T> filter) {
    return Query<T>(this, filters: [filter]);
  }
}
