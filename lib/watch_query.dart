part of loon;

typedef WatchQuerySnapshotDiff<T> = (
  List<DocumentSnapshot<T>> prevSnap,
  List<DocumentSnapshot<T>> snap
);

class WatchQuery<T> extends Query<T> {
  final _controller = StreamController<WatchQuerySnapshotDiff<T>>.broadcast();
  late final Stream<List<DocumentSnapshot<T>>> _snapshotStream;
  late List<DocumentSnapshot<T>> snapshot;
  List<DocumentSnapshot<T>> prevSnapshot = [];

  WatchQuery(
    super.collection, {
    required super.filter,
    required super.fromJson,
    required super.toJson,
    required super.persistorSettings,
  }) {
    _snapshotStream = _controller.stream.map((record) {
      final (_, snap) = record;
      return snap;
    });

    snapshot = get();
    _controller.add((prevSnapshot, snapshot));
    Loon.instance._registerWatchQuery(this);
  }

  void dispose() {
    _controller.close();
    Loon.instance._unregisterWatchQuery(this);
  }

  Stream<List<DocumentSnapshot<T>>> get stream {
    return _snapshotStream;
  }

  Stream<WatchQuerySnapshotDiff<T>> get changes {
    return _controller.stream;
  }

  /// On broadcast, the watch examines all documents that have been added, removed or modified
  /// since the last broadcast and determines if the query needs to re-emit an updated list.
  /// The query could be dirty if any of the following are true:
  /// 1. A new document has been added that satisfies the query filter.
  /// 2. A document that previously satisfied the query filter has been removed.
  /// 3. A document that has been modified and meets one of the following requirements:
  ///   a) Previously satisfied the query filter and now does not.
  ///   b) Previously did not satisfy the query filter and now does.
  ///   c) Previously satisfied the query filter and still does (since its modified data must be delivered on the query).
  void _onBroadcast() {
    bool shouldBroadcast = false;

    // If the entire collection has been deleted, then clear the snapshot.
    if (!Loon.instance._hasCollection(collection)) {
      snapshot = [];
      _controller.add((prevSnapshot, snapshot));
      return;
    }

    final broadcastDocs = Loon.instance._getBroadcastDocuments<T>(
      collection,
      fromJson: fromJson,
      toJson: toJson,
      persistorSettings: persistorSettings,
    );

    if (broadcastDocs.isEmpty) {
      return;
    }

    final existingDocs = snapshot.map((snap) => snap.doc).toList();
    final queryDocIds = existingDocs.map((doc) => doc.id).toSet();

    final docsById = [
      ...existingDocs,
      ...broadcastDocs,
    ].fold({}, (acc, doc) {
      return {
        ...acc,
        doc.id: doc,
      };
    });

    final addedDocsIds = _resolveQuery(
      broadcastDocs
          .where((doc) => doc.type == BroadcastEventTypes.added)
          .toList(),
    ).map((doc) => doc.id).toSet();

    // 1. Add new documents that satisfy the query filter.
    if (addedDocsIds.isNotEmpty) {
      queryDocIds.addAll(addedDocsIds);
      shouldBroadcast = true;
    }

    final removedDocIds = broadcastDocs
        .where((doc) =>
            doc.type == BroadcastEventTypes.removed &&
            queryDocIds.contains(doc.id))
        .map((doc) => doc.id)
        .toSet();

    // 2. Remove old documents that previously satisfied the query filter and have been removed.
    if (removedDocIds.isNotEmpty) {
      queryDocIds.removeAll(removedDocIds);
      shouldBroadcast = true;
    }

    final modifiedDocs = broadcastDocs
        .where((doc) => doc.type == BroadcastEventTypes.modified)
        .toList();
    final modifiedDocIds = modifiedDocs.map((doc) => doc.id).toSet();
    final existingModifiedDocIds = modifiedDocIds.intersection(queryDocIds);

    // The document IDs of the modified documents that satisfy the query filter.
    final filteredModifiedDocIds =
        _resolveQuery(modifiedDocs).map((doc) => doc.id).toSet();
    final filteredModifiedDocIdsToAdd =
        filteredModifiedDocIds.difference(existingModifiedDocIds);

    // 3.a) Add any modified documents that now satisfy the query filter.
    if (filteredModifiedDocIdsToAdd.isNotEmpty) {
      queryDocIds.addAll(filteredModifiedDocIds);
      shouldBroadcast = true;
    }

    final modifiedDocIdsToRemove =
        existingModifiedDocIds.difference(filteredModifiedDocIds);

    // 3,b) Remove any modified documents that no longer satisfy the query filter.
    if (modifiedDocIdsToRemove.isNotEmpty) {
      queryDocIds.removeAll(modifiedDocIdsToRemove);
    }

    // 3.c) If any existing doc that still satisfies the query has been modified, then its new data must be delivered.
    if (existingModifiedDocIds.isNotEmpty) {
      shouldBroadcast = true;
    }

    if (shouldBroadcast) {
      prevSnapshot = snapshot;
      snapshot = queryDocIds
          .map(
            (docId) => docsById[docId].get(),
          )
          .whereType<DocumentSnapshot<T>>()
          .toList();

      _controller.add((prevSnapshot, snapshot));
    }
  }
}
