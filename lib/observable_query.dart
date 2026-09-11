part of 'loon.dart';

class ObservableQuery<T> extends Query<T>
    with
        BroadcastObserver<List<DocumentSnapshot<T>>,
            List<DocumentChangeSnapshot<T>>> {
  /// An observable query maintains a cache of snapshots of the documents in its current result set.
  final Map<Document<T>, DocumentSnapshot<T>> _snapCache = {};

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

    _init(snaps, multicast: multicast);
  }

  /// Caches the snapshot of a document in the result set.
  void _cacheDoc(DocumentSnapshot<T> snap) {
    _snapCache[snap.doc] = snap;
  }

  /// Removes the document from the result set cache.
  void _evictDoc(Document<T> doc) {
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
  ///   c. A document that has been modified/touched and meets one of the following requirements:
  ///     i. Previously satisfied the query filter and still does (since its modified data must be delivered on the query).
  ///     ii. Previously satisfied the query filter and now does not.
  ///     iii. Previously did not satisfy the query filter and now does.
  @override
  void _onBroadcast() {
    try {
      bool shouldRebroadcast = false;

      // The list of changes to the query. Note that the [BroadcastEvents] of the document
      // local to the query are different from the global broadcast events. For example, if a document
      // was modified globally such that now it should be included in the query and before was not,
      // then its event type at the query-level is [BroadcastEvents.added] while its global event was
      // [EventTypes.modified].
      final List<DocumentChangeSnapshot<T>> changeSnaps = [];
      final hasChangeListener = _changeController.hasListener;

      // 1.  Any path along the query's collection path has been removed.
      if (Loon._instance.broadcastManager.eventStore
              .getNearestMatch(path, BroadcastEvents.removed) !=
          null) {
        final controllerValue = _controllerValue;
        if (controllerValue != null && controllerValue.isNotEmpty) {
          shouldRebroadcast = true;

          changeSnaps.addAll(
            controllerValue.map(
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
        }
      }

      final events = Loon._instance.broadcastManager.eventStore
          .getChildValues(collection.path);
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

                shouldRebroadcast = true;

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
              } else if (_snapCache.containsKey(doc)) {
                // The document was in the result set but a delete + recreate that
                // coalesced into a single added event (or a re-add) now fails the
                // filter, so the stale entry must be evicted.
                _evictDoc(doc);

                shouldRebroadcast = true;

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
            case BroadcastEvents.removed:
              // 2.b Remove old documents that previously satisfied the query filter and have been removed.
              if (_snapCache.containsKey(doc)) {
                _evictDoc(doc);

                shouldRebroadcast = true;

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

            // 2.c Re-evaluate modified/touched documents. A touched document is re-evaluated in the
            // same way as a modified one, since a touch signals that state its filter or sort depends on
            // may have changed outside of the store.
            case BroadcastEvents.modified:
            case BroadcastEvents.touched:
              // A touched document that does not exist has no value to re-evaluate.
              if (snap == null) {
                break;
              }

              if (_snapCache.containsKey(doc)) {
                shouldRebroadcast = true;

                // 2.c.i Previously satisfied the query filter and still does (updated value must still be rebroadcast on the query).
                if (_filter(snap)) {
                  _cacheDoc(snap);

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
                if (_filter(snap)) {
                  _cacheDoc(snap);

                  shouldRebroadcast = true;

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
          }
        }
      }

      if (changeSnaps.isNotEmpty) {
        _changeController.add(changeSnaps);
      }

      // If the query should be rebroadcast, then it emits its cached value if a read already
      // recomputed it since it was invalidated, otherwise it rebuilds it from the snapshot cache.
      if (shouldRebroadcast) {
        final updatedValue =
            _value ?? (_value = _sortQuery(_snapCache.values.toList()));
        add(updatedValue);
      }
    } catch (error, stackTrace) {
      // An observer can throw while processing a broadcast, for example if a query's filter throws.
      // The error is reported rather than thrown so that the remaining observers still process the
      // broadcast, since its events are cleared once it completes.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'loon',
          context: ErrorDescription(
            'while broadcasting observer of $_observerId',
          ),
        ),
      );
    }
  }

  @override
  ObservableQuery<T> observe({
    bool multicast = false,
  }) {
    return this;
  }

  @override
  get isDirty => _value == null;

  @override
  get() {
    return isDirty ? (_value = super.get()) : _value!;
  }

  Map inspect() {
    return {
      "docSnaps": _snapCache,
    };
  }
}
