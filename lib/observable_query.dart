part of loon;

class ObservableQuery<T> extends Query<T>
    with
        BroadcastObserver<List<DocumentSnapshot<T>>,
            List<DocumentChangeSnapshot<T>>> {
  /// A query maintains a cache of snapshots of the documents in its current result set.
  final Map<Document<T>, DocumentSnapshot<T>> _snapIndex = {};

  /// A query maintains a cache of the dependencies of documents in its current result set.
  final Map<Document<T>, Set<Document>> _dependenciesIndex = {};

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

  /// Caches the document in the query. This involves:
  /// 1. Caching the document data snapshot and dependencies in the query's document cache.
  /// 2. Updating the query's dependencies to remove the document's previous dependencies
  ///    and adding the new ones.
  void _cacheDoc(DocumentSnapshot<T> snap) {
    final doc = snap.doc;
    final prevDeps = _dependenciesIndex[doc];
    final deps = doc.dependencies();

    _snapIndex[doc] = snap;

    if (!setEquals(deps, prevDeps)) {
      if (deps != null) {
        _dependenciesIndex[doc] = deps;

        for (final dep in deps) {
          _deps.inc(dep.path);
        }
      } else if (prevDeps != null) {
        _dependenciesIndex.remove(doc);

        for (final dep in prevDeps) {
          _deps.dec(dep.path);
        }
      }
    }
  }

  /// Removes the doc from the cache, clearing it in both the snapshot and dependencies indices.
  void _removeDoc(Document<T> doc) {
    final deps = _dependenciesIndex[doc];

    if (deps != null) {
      for (final dep in deps) {
        _deps.dec(dep.path);
      }
    }

    _dependenciesIndex.remove(doc);
    _snapIndex.remove(doc);
  }

  /// On broadcast, the [ObservableQuery] examines the broadcast events that have occurred
  /// since the last broadcast and determines if the query needs to rebroadcast to its listeners.
  ///
  /// The conditions for rebroadcasting the updated query are as follows:
  ///
  /// 1. The query's collection has a broadcast event.
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

    // 1. The query's collection has a broadcast event.
    if (Loon._instance.broadcastManager.store.get(collection.path) ==
            EventTypes.removed &&
        _value.isNotEmpty) {
      _changeController.add(_value.map((snap) {
        return DocumentChangeSnapshot<T>(
          doc: snap.doc,
          event: EventTypes.removed,
          prevData: snap.data,
          data: null,
        );
      }).toList());

      _snapIndex.clear();
      _deps.clear();
      add([]);
      return;
    }

    final events =
        Loon._instance.broadcastManager.store.getAll(collection.path);
    if (events != null) {
      // The list of changes to the query. Note that the [EventTypes] of the document
      // local to the query are different from the global broadcast events. For example, if a document
      // was modified globally such that now it should be included in the query and before was not,
      // then its event type at the query-level is [BroadcastEventTypes.added] while its global event was
      // [BroadcastEventTypes.modified].
      final List<DocumentChangeSnapshot<T>> changeSnaps = [];
      final hasChangeListener = _changeController.hasListener;

      for (final entry in events.entries) {
        final docId = entry.key;
        final event = entry.value;

        final doc = collection.doc(docId);
        final prevSnap = _snapIndex[doc];
        final snap = doc.get();

        switch (event) {
          case EventTypes.added:
          case EventTypes.hydrated:
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
          case EventTypes.removed:
            // 2.b Remove old documents that previously satisfied the query filter and have been removed.
            if (_snapIndex.containsKey(doc)) {
              _removeDoc(doc);

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

          // 2.c Add / remove modified documents.
          case EventTypes.modified:
            if (_snapIndex.containsKey(doc)) {
              shouldUpdate = true;

              // 2.c.i Previously satisfied the query filter and still does (updated value must still be rebroadcast on the query).
              if (_filter(snap!)) {
                _cacheDoc(snap);

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
                /// 2.c.ii Previously satisfied the query filter and now does not.
                _removeDoc(doc);

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
              // 2.c.iii Previously did not satisfy the query filter and now does.
              if (_filter(snap!)) {
                _cacheDoc(snap);

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
          // 2.d If the broadcast documents include any documents that were manually touched for rebroadcast and are part of this query's
          // result set, then the query should be rebroadcasted.
          case EventTypes.touched:
            if (_snapIndex.containsKey(doc)) {
              _cacheDoc(snap!);

              shouldRebroadcast = true;

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

      if (changeSnaps.isNotEmpty) {
        _changeController.add(changeSnaps);
      }
    }

    // 3. The query itself has been touched for rebroadcast.
    if (Loon._instance.broadcastManager.store.get(path) == EventTypes.touched) {
      shouldRebroadcast = true;
    }

    if (shouldUpdate) {
      add(_sortQuery(_snapIndex.values.toList()));
    } else if (shouldRebroadcast) {
      add(_value);
    }
  }

  @override
  ObservableQuery<T> observe({bool multicast = false}) {
    return this;
  }

  @override
  get() {
    // If the query is pending a broadcast when its data is accessed, we must immediately
    // run the broadcast instead of waiting until the next micro-task in order to return the latest value.
    if (isScheduledForBroadcast()) {
      _onBroadcast();
    }
    return _value;
  }
}
