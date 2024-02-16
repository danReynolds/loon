part of loon;

class ObservableQuery<T> extends Query<T>
    with
        BroadcastObserver<List<DocumentSnapshot<T>>,
            List<DocumentChangeSnapshot<T>>> {
  /// A cache of the snapshots broadcasted by the query indexed by their [Document] ID.
  final Map<String, DocumentSnapshot<T>> _index = {};

  ObservableQuery(
    super.collection, {
    required super.filters,
    required super.sort,
    required super.fromJson,
    required super.toJson,
    required super.persistorSettings,
    required super.dependenciesBuilder,
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
    final docBroadcasts = Loon._instance._documentBroadcastStore[name];

    if (docBroadcasts == null) {
      return;
    }

    /// The list of changes to the query. Note that the [DocumentBroadcastTypes] of the document
    /// local to the query is different from the global broadcast type. For example, if a document
    /// was modified globally such that now it should be included in the query and before was not,
    /// then its event type reported by the query is [DocumentBroadcastTypes.added] and its global event was
    /// [DocumentBroadcastTypes.modified].
    final List<DocumentChangeSnapshot<T>> changeSnaps = [];
    bool shouldUpdate = false;

    for (final docBroadcast in docBroadcasts.entries) {
      final docId = docBroadcast.key;
      final broadcastType = docBroadcast.value;

      final snap = Loon._instance._getSnapshot<T>(
        id: docId,
        collection: name,
        fromJson: fromJson,
        toJson: toJson,
        persistorSettings: persistorSettings,
      );

      final prevSnap = _index[docId];
      final hasChangeListener = _changeController.hasListener;

      switch (broadcastType) {
        case DocumentBroadcastTypes.added:
        case DocumentBroadcastTypes.hydrated:
          // 1. Add new documents that satisfy the query filter.
          if (_filter(snap!)) {
            _index[docId] = snap;
            shouldUpdate = true;

            if (hasChangeListener) {
              changeSnaps.add(
                DocumentChangeSnapshot(
                  doc: snap.doc,
                  type: broadcastType,
                  prevData: prevSnap?.data,
                  data: snap.data,
                ),
              );
            }
          }
          break;
        case DocumentBroadcastTypes.removed:
          // 2. Remove old documents that previously satisfied the query filter and have been removed.
          if (_index.containsKey(docId)) {
            final doc = _index[docId]!.doc;
            _index.remove(docId);
            shouldUpdate = true;

            if (hasChangeListener) {
              changeSnaps.add(
                DocumentChangeSnapshot(
                  doc: doc,
                  type: DocumentBroadcastTypes.removed,
                  prevData: prevSnap?.data,
                  data: null,
                ),
              );
            }
          }
          break;

        // 3.a) Add / remove modified documents.
        case DocumentBroadcastTypes.modified:
          if (_index.containsKey(docId)) {
            shouldUpdate = true;

            // a) Previously satisfied the query filter and still does (updated value must still be rebroadcast on the query).
            if (_filter(snap!)) {
              _index[docId] = snap;

              if (hasChangeListener) {
                changeSnaps.add(
                  DocumentChangeSnapshot(
                    doc: snap.doc,
                    type: DocumentBroadcastTypes.modified,
                    prevData: prevSnap?.data,
                    data: snap.data,
                  ),
                );
              }
            } else {
              /// b) Previously satisfied the query filter and now does not.
              final doc = _index[docId]!.doc;
              _index.remove(docId);

              if (hasChangeListener) {
                changeSnaps.add(
                  DocumentChangeSnapshot(
                    doc: doc,
                    type: DocumentBroadcastTypes.removed,
                    prevData: prevSnap?.data,
                    data: null,
                  ),
                );
              }
            }
          } else {
            // c) Previously did not satisfy the query filter and now does.
            if (_filter(snap!)) {
              _index[docId] = snap;
              shouldUpdate = true;

              if (hasChangeListener) {
                changeSnaps.add(
                  DocumentChangeSnapshot(
                    doc: snap.doc,
                    type: DocumentBroadcastTypes.added,
                    prevData: prevSnap?.data,
                    data: snap.data,
                  ),
                );
              }
            }
          }
          break;
        // 4. If the broadcast documents include any documents that were manually touched for rebroadcast and are part of this query's
        // result set, then the query should be rebroadcasted.
        case DocumentBroadcastTypes.touched:
          if (_index.containsKey(docId)) {
            _index[docId] = snap!;
            shouldUpdate = true;

            if (hasChangeListener) {
              changeSnaps.add(
                DocumentChangeSnapshot(
                  doc: snap.doc,
                  type: DocumentBroadcastTypes.touched,
                  prevData: prevSnap?.data,
                  data: snap.data,
                ),
              );
            }
          }
          break;
      }
    }

    if (shouldUpdate) {
      add(_sortQuery(_index.values.toList()));

      if (changeSnaps.isNotEmpty) {
        _changeController.add(changeSnaps);
      }
    }
  }

  @override
  ObservableQuery<T> observe({bool multicast = false}) {
    return this;
  }

  @override
  get() {
    // If the query is pending a broadcast when its data is accessed, we must immediately
    // run the broadcast instead of waiting until the next micro-task and return the updated value.
    if (Loon._instance._isQueryPendingBroadcast(this)) {
      _onBroadcast();
    }
    return _value;
  }
}
