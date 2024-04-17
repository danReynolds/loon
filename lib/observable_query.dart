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
    final broadcasts =
        Loon._instance._broadcastManager.getBroadcasts(collection);

    if (broadcasts == null) {
      return;
    }

    /// The list of changes to the query. Note that the [BroadcastEventTypes] of the document
    /// local to the query is different from the global broadcast type. For example, if a document
    /// was modified globally such that now it should be included in the query and before was not,
    /// then its event type reported by the query is [BroadcastEventTypes.added] and its global event was
    /// [BroadcastEventTypes.modified].
    final List<DocumentChangeSnapshot<T>> changeSnaps = [];
    final hasChangeListener = _changeController.hasListener;
    bool shouldUpdate = false;

    for (final docBroadcast in broadcasts.entries) {
      final docId = docBroadcast.key;
      final event = docBroadcast.value;

      final prevSnap = _index[docId];
      final snap = collection.doc(docId).get();

      switch (event) {
        case EventTypes.added:
        case EventTypes.hydrated:
          // 1. Add new documents that satisfy the query filter.
          if (_filter(snap!)) {
            _index[docId] = snap;
            shouldUpdate = true;

            if (hasChangeListener) {
              changeSnaps.add(
                DocumentChangeSnapshot(
                  doc: snap.doc,
                  event: event,
                  prevData: prevSnap?.data,
                  data: snap.data,
                ),
              );
            }
          }
          break;
        case EventTypes.removed:
          // 2. Remove old documents that previously satisfied the query filter and have been removed.
          if (_index.containsKey(docId)) {
            final doc = _index[docId]!.doc;
            _index.remove(docId);
            shouldUpdate = true;

            if (hasChangeListener) {
              changeSnaps.add(
                DocumentChangeSnapshot(
                  doc: doc,
                  event: EventTypes.removed,
                  prevData: prevSnap?.data,
                  data: null,
                ),
              );
            }
          }
          break;

        // 3.a) Add / remove modified documents.
        case EventTypes.modified:
          if (_index.containsKey(docId)) {
            shouldUpdate = true;

            // a) Previously satisfied the query filter and still does (updated value must still be rebroadcast on the query).
            if (_filter(snap!)) {
              _index[docId] = snap;

              if (hasChangeListener) {
                changeSnaps.add(
                  DocumentChangeSnapshot(
                    doc: snap.doc,
                    event: EventTypes.modified,
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
                    event: EventTypes.removed,
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
                    event: EventTypes.added,
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
        case EventTypes.touched:
          if (_index.containsKey(docId)) {
            _index[docId] = snap!;
            shouldUpdate = true;

            if (hasChangeListener) {
              changeSnaps.add(
                DocumentChangeSnapshot(
                  doc: snap.doc,
                  event: EventTypes.touched,
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
  _onClear() {
    if (_changeController.hasListener) {
      _changeController.add(_index.values.map((prevSnap) {
        return DocumentChangeSnapshot<T>(
          doc: prevSnap.doc,
          event: EventTypes.removed,
          prevData: prevSnap.data,
          data: null,
        );
      }).toList());
    }

    _index.clear();
    add([]);
  }

  @override
  ObservableQuery<T> observe({bool multicast = false}) {
    return this;
  }

  @override
  get() {
    // If the query is pending a broadcast when its data is accessed, we must immediately
    // run the broadcast instead of waiting until the next micro-task in order to return the latest value.
    if (Loon._instance._broadcastManager.contains(path)) {
      _onBroadcast();
    }
    return _value;
  }
}
