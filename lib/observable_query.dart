part of loon;

class ObservableQuery<T> extends Query<T>
    with
        Observable<List<DocumentSnapshot<T>>>,
        BroadcastObserver<List<DocumentSnapshot<T>>,
            List<BroadcastDocument<T>>> {
  /// A cache of the snapshots broadcasted by the query indexed by their [Document] ID.
  final Map<String, DocumentSnapshot<T>> _index = {};

  ObservableQuery(
    super.collection, {
    required super.filters,
    required super.sort,
    required super.fromJson,
    required super.toJson,
    required super.persistorSettings,
    required bool multicast,
  }) {
    final snaps = super.get();
    for (final snap in snaps) {
      _index[snap.id] = snap;
    }

    init(snaps, multicast: multicast);
  }

  /// On broadcast, the [ObservableQuery] examines the documents that have been added, removed or modified
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
      add([]);
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

    /// The list of meta changes to the query. Note that the [BroadcastEventTypes] of the document
    /// local to the query is different from the globally broadcast event. For example, if a document
    /// was modified globally such that now it should be included in the query and before was not,
    /// then its event type reported by the query is [BroadcastEventTypes.added] and its global event was
    /// [BroadcastEventTypes.modified].
    final List<BroadcastDocument<T>> metaBroadcastDocs = [];

    for (final broadcastDoc in broadcastDocs) {
      final docId = broadcastDoc.id;

      switch (broadcastDoc.type) {
        case BroadcastEventTypes.added:
          final snap = broadcastDoc.get()!;

          // 1. Add new documents that satisfy the query filter.
          if (_filter(snap)) {
            metaBroadcastDocs.add(
              BroadcastDocument(broadcastDoc, BroadcastEventTypes.added),
            );

            shouldBroadcast = true;
            _index[docId] = snap;
          }
          break;
        case BroadcastEventTypes.removed:
          // 2. Remove old documents that previously satisfied the query filter and have been removed.
          if (_index.containsKey(docId)) {
            metaBroadcastDocs.add(
              BroadcastDocument(broadcastDoc, BroadcastEventTypes.removed),
            );

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

              metaBroadcastDocs.add(
                BroadcastDocument(broadcastDoc, BroadcastEventTypes.modified),
              );
            } else {
              metaBroadcastDocs.add(
                BroadcastDocument(broadcastDoc, BroadcastEventTypes.removed),
              );

              /// b) Previously satisfied the query filter and now does not.
              _index.remove(docId);
            }
          } else {
            metaBroadcastDocs.add(
              BroadcastDocument(broadcastDoc, BroadcastEventTypes.added),
            );

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
            metaBroadcastDocs.add(
              BroadcastDocument(broadcastDoc, BroadcastEventTypes.touched),
            );

            _index[docId] = broadcastDoc.get()!;
            shouldBroadcast = true;
          }
          break;
      }
    }

    if (metaBroadcastDocs.isNotEmpty) {
      _metaChangesController.add(metaBroadcastDocs);
    }

    if (shouldBroadcast) {
      final snaps = _sortQuery(_index.values.toList());
      add(snaps);
    }
  }

  @override
  ObservableQuery<T> observe({bool multicast = false}) {
    return this;
  }

  @override
  get() {
    if (Loon._instance._isQueryPendingBroadcast(this)) {
      return super.get();
    }
    return _value;
  }
}
