part of loon;

class ObservableQuery<T> extends Query<T>
    with BroadcastObservable<List<DocumentSnapshot<T>>> {
  /// A cache of the snapshots broadcasted by the query indexed by their [Document] ID.
  final Map<String, DocumentSnapshot<T>> _index = {};

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

  /// On broadcast, the query examines the documents that have been added, removed or modified
  /// since the last broadcast and determines if the query needs to rebroadcast to its observers.
  /// The conditions for rebroadcasting the updated query are as follows:
  /// 1. A new document has been added that satisfies the query filter.
  /// 2. A document that previously satisfied the query filter has been removed.
  /// 3. A document that has been modified and meets one of the following requirements:
  ///   a) Previously satisfied the query filter and still does (since its modified data must be delivered on the query).
  ///   b) Previously satisfied the query filter and now does not.
  ///   c) Previously did not satisfy the query filter and now does.
  /// 4. A document that has been manually touched to be rebroadcasted.
  @override
  void _onBroadcast() {
    bool shouldBroadcast = false;

    // If the entire collection has been deleted, then clear the snapshot.
    if (!Loon._instance._hasCollection(collection)) {
      _index.clear();
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

    for (final broadcastDoc in broadcastDocs) {
      final docId = broadcastDoc.id;

      switch (broadcastDoc.type) {
        case BroadcastEventTypes.added:
          final snap = broadcastDoc.get()!;

          // 1. Add new documents that satisfy the query filter.
          if (_filter(snap)) {
            shouldBroadcast = true;
            _index[docId] = snap;
          }
          break;
        case BroadcastEventTypes.removed:
          // 2. Remove old documents that previously satisfied the query filter and have been removed.
          if (_index.containsKey(docId)) {
            _index.remove(docId);
            shouldBroadcast = true;
          }
          break;

        // 3.a) Add / remove modified documents.
        case BroadcastEventTypes.modified:
          final updatedSnap = broadcastDoc.get()!;

          if (_index.containsKey(docId)) {
            shouldBroadcast = true;

            // a) Previously satisfied the query filter and still does (updated value must still be rebroadcast on the query).
            if (_filter(updatedSnap)) {
              _index[docId] = updatedSnap;
            } else {
              /// b) Previously satisfied the query filter and now does not.
              _index.remove(docId);
            }
          } else {
            // c) Previously did not satisfy the query filter and now does.
            if (_filter(updatedSnap)) {
              _index[docId] = updatedSnap;
              shouldBroadcast = true;
            }
          }
          break;
        // 4. If the broadcast documents include any documents that were manually touched for rebroadcast and are part of this query's
        // result set, then the query should be rebroadcasted.
        case BroadcastEventTypes.touched:
          if (_index.containsKey(docId)) {
            _index[docId] = broadcastDoc.get()!;
            shouldBroadcast = true;
          }
          break;
      }
    }

    if (shouldBroadcast) {
      final snaps = _sortQuery(_index.values.toList());

      rebroadcast(snaps);
    }
  }
}
