part of loon;

class ObservableQuery<T> extends Query<T>
    with
        BroadcastObserver<List<DocumentSnapshot<T>>,
            List<DocumentChangeSnapshot<T>>> {
  /// A query maintains a cache of snapshots of the documents in its current result set.
  final Map<Document<T>, DocumentSnapshot<T>> _snapCache = {};

  /// A query maintains a cache of the dependencies of documents in its current result set.
  final Map<Document<T>, Set<Document>> _depCache = {};

  ObservableQuery(
    super.collection, {
    required super.filters,
    required super.sort,
    required bool multicast,
  }) {
    final snaps = super.get();
    for (final snap in snaps) {
      _cacheDoc(snap);
    }

    init(snaps, multicast: multicast);
  }

  /// Update the doc in the snapshot and dependency indices.
  void _cacheDoc(DocumentSnapshot<T> snap) {
    final doc = snap.doc;
    final prevDeps = _depCache[doc];
    final deps = doc.dependencies();

    _snapCache[doc] = snap;

    if (deps != prevDeps) {
      if (deps != null) {
        _depCache[doc] = deps;

        for (final dep in deps) {
          _deps.inc(dep.path);
        }
      } else if (prevDeps != null) {
        _depCache.remove(doc);

        for (final dep in prevDeps) {
          _deps.dec(dep.path);
        }
      }
    }
  }

  /// Removes the doc from the index, clearing it in both the snapshot and dependency indices.
  void _evictDoc(Document<T> doc) {
    final deps = _depCache[doc];

    if (deps != null) {
      for (final dep in deps) {
        _deps.dec(dep.path);
      }
    }

    _depCache.remove(doc);
    _snapCache.remove(doc);
  }

  /// On broadcast, the [ObservableQuery] examines the events that have occurred
  /// since the last broadcast and determines if the query needs to be rebroadcast.
  ///
  /// The scenarios for rebroadcasting the updated query are as follows:
  ///
  /// 1. Any path above or equal to the query's collection has been removed.
  /// 2. The query collection documents have broadcast events. These events include:
  ///   a. A new document has been added that satisfies the query filter.
  ///   b. A document that previously satisfied the query filter has been removed.
  ///   c. A document that has been modified and meets one of the following requirements:
  ///     i. Previously satisfied the query filter and still does (since its modified data must be delivered on the query).
  ///     ii. Previously satisfied the query filter and now does not.
  ///     iii. Previously did not satisfy the query filter and now does.
  ///   d. A document that has been manually touched to be rebroadcasted.
  /// 3. The query itself has been touched for rebroadcast (such as when its dependencies have been marked as dirty).
  @override
  void _onBroadcast() {
    bool shouldRebroadcast = false;
    bool shouldUpdate = false;

    // The list of changes to the query. Note that the [BroadcastEvents] of the document
    // local to the query are different from the global broadcast events. For example, if a document
    // was modified globally such that now it should be included in the query and before was not,
    // then its event type at the query-level is [BroadcastEventTypes.added] while its global event was
    // [BroadcastEventTypes.modified].
    final List<DocumentChangeSnapshot<T>> changeSnaps = [];
    final hasChangeListener = _changeController.hasListener;

    // 1.  Any path above or equal to the query's collection has been removed. This is determined by finding
    //     a [BroadcastEvents.removed] event anywhere above or at the query's collection path.
    if (Loon._instance.broadcastManager.store
            .findValue(path, BroadcastEvents.removed) !=
        null) {
      if (_value.isNotEmpty) {
        shouldUpdate = true;

        changeSnaps.addAll(
          _value.map(
            (snap) {
              return DocumentChangeSnapshot<T>(
                doc: snap.doc,
                event: BroadcastEvents.removed,
                prevData: snap.data,
                data: null,
              );
            },
          ),
        );

        _snapCache.clear();
        _deps.clear();
      }
    }

    final events =
        Loon._instance.broadcastManager.store.getChildValues(collection.path);
    if (events != null) {
      for (final entry in events.entries) {
        final docId = entry.key;
        final event = entry.value;

        final doc = collection.doc(docId);
        final prevSnap = _snapCache[doc];
        final snap = doc.get();

        switch (event) {
          case BroadcastEvents.added:
          case BroadcastEvents.hydrated:
            // 2.a Add new documents that satisfy the query filter.
            if (_filter(snap!)) {
              _cacheDoc(snap);

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
          case BroadcastEvents.removed:
            // 2.b Remove old documents that previously satisfied the query filter and have been removed.
            if (_snapCache.containsKey(doc)) {
              _evictDoc(doc);

              shouldUpdate = true;

              if (hasChangeListener) {
                changeSnaps.add(
                  DocumentChangeSnapshot(
                    doc: doc,
                    event: BroadcastEvents.removed,
                    prevData: prevSnap?.data,
                    data: null,
                  ),
                );
              }
            }
            break;

          // 2.c Add / remove modified documents.
          case BroadcastEvents.modified:
            if (_snapCache.containsKey(doc)) {
              shouldUpdate = true;

              // 2.c.i Previously satisfied the query filter and still does (updated value must still be rebroadcast on the query).
              if (_filter(snap!)) {
                _cacheDoc(snap);

                if (hasChangeListener) {
                  changeSnaps.add(
                    DocumentChangeSnapshot(
                      doc: snap.doc,
                      event: BroadcastEvents.modified,
                      prevData: prevSnap?.data,
                      data: snap.data,
                    ),
                  );
                }
              } else {
                /// 2.c.ii Previously satisfied the query filter and now does not.
                _evictDoc(doc);

                if (hasChangeListener) {
                  changeSnaps.add(
                    DocumentChangeSnapshot(
                      doc: doc,
                      event: BroadcastEvents.removed,
                      prevData: prevSnap?.data,
                      data: null,
                    ),
                  );
                }
              }
            } else {
              // 2.c.iii Previously did not satisfy the query filter and now does.
              if (_filter(snap!)) {
                _cacheDoc(snap);

                shouldUpdate = true;

                if (hasChangeListener) {
                  changeSnaps.add(
                    DocumentChangeSnapshot(
                      doc: snap.doc,
                      event: BroadcastEvents.added,
                      prevData: prevSnap?.data,
                      data: snap.data,
                    ),
                  );
                }
              }
            }
            break;
          // 2.d If the broadcast documents include any documents that were manually touched for rebroadcast and are part of this query's
          // result set, then the query should be rebroadcasted.
          case BroadcastEvents.touched:
            if (_snapCache.containsKey(doc)) {
              shouldRebroadcast = true;

              if (hasChangeListener) {
                changeSnaps.add(
                  DocumentChangeSnapshot(
                    doc: snap!.doc,
                    event: BroadcastEvents.touched,
                    prevData: prevSnap?.data,
                    data: snap.data,
                  ),
                );
              }
            }
            break;
        }
      }
    }

    // 3. The query itself has been touched for rebroadcast.
    if (Loon._instance.broadcastManager.store.get(path) ==
        BroadcastEvents.touched) {
      shouldRebroadcast = true;
    }

    if (changeSnaps.isNotEmpty) {
      _changeController.add(changeSnaps);
    }

    if (shouldUpdate) {
      add(_sortQuery(_snapCache.values.toList()));
    } else if (shouldRebroadcast) {
      add(_value);
    }
  }

  @override
  ObservableQuery<T> observe({
    bool multicast = false,
  }) {
    return this;
  }

  @override
  get() {
    // If the query is pending broadcast when its data is accessed, then it must not use
    // its cached value as that value is stale until the query has processed the broadcast.
    if (isPendingBroadcast()) {
      return super.get();
    }
    return _value;
  }
}
