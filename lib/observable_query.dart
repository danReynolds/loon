part of loon;

class ObservableQuery<T> extends Query<T>
    with BroadcastObservable<List<DocumentSnapshot<T>>> {
  ObservableQuery(
    super.collection, {
    required super.filters,
    required super.sort,
    required super.fromJson,
    required super.toJson,
    required super.persistorSettings,
  }) {
    observe([]);
  }

  /// On broadcast, the watch examines all documents that have been added, removed or modified
  /// since the last broadcast and determines if the query needs to rebroadcast to observers. The conditions
  /// for rebroadcasting the updated query are the following:
  /// 1. A new document has been added that satisfies the query filter.
  /// 2. A document that previously satisfied the query filter has been removed.
  /// 3. A document that has been modified and meets one of the following requirements:
  ///   a) Previously satisfied the query filter and now does not.
  ///   b) Previously did not satisfy the query filter and now does.
  ///   c) Previously satisfied the query filter and still does (since its modified data must be delivered on the query).
  /// 4. A document that has been manually touched to be rebroadcasted.
  @override
  void _onBroadcast() {
    bool shouldBroadcast = false;

    // If the entire collection has been deleted, then clear the snapshot.
    if (!Loon._instance._hasCollection(collection)) {
      rebroadcast([]);
      return;
    }

    final broadcastDocs = Loon._instance._getBroadcastDocuments<T>(
      collection,
      fromJson: fromJson,
      toJson: toJson,
      persistorSettings: persistorSettings,
    );

    if (broadcastDocs.isEmpty) {
      return;
    }

    final existingDocs = value.map((snap) => snap.doc).toList();
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

    final addedDocsIds = _filterQuery(
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
        _filterQuery(modifiedDocs).map((doc) => doc.id).toSet();
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

    // 4. If the broadcast documents include any documents that were manually touched for rebroadcast and are part of this query's
    // result set, then the query should be rebroadcasted.
    final touchedDocs = broadcastDocs
        .where((doc) =>
            doc.type == BroadcastEventTypes.touched &&
            queryDocIds.contains(doc.id))
        .toList();
    if (touchedDocs.isNotEmpty) {
      shouldBroadcast = true;
    }

    if (shouldBroadcast) {
      final snaps = _sortQuery(
        queryDocIds
            .map(
              (docId) => docsById[docId].get(),
            )
            .whereType<DocumentSnapshot<T>>()
            .toList(),
      );

      rebroadcast(snaps);
    }
  }
}
