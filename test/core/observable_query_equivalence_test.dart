import 'dart:math';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';

import '../utils.dart';

/// Equivalence fuzzer for [ObservableQuery].
///
/// An observable query maintains its result incrementally: on each broadcast it
/// inspects only the changed documents and patches a cached result, rather than
/// recomputing from scratch. The property under test is that this incremental
/// result always equals a fresh full recompute of the same query
/// (`Query.get()`), which filters and sorts the whole collection and is the
/// simple oracle.
///
/// Each test drives one long random walk of create/update/delete operations
/// over a small id/value space, so documents repeatedly cross the filter
/// boundary, exercising the added/removed/modified transitions in
/// `_onBroadcast`, and compares the value most recently emitted on the query's
/// stream against the oracle after every step. A failing case replays from its
/// seed, sorted flag, and threshold.
///
/// A total-order comparator (value then id) keeps the sorted result unambiguous
/// so it can be compared as an ordered list; the unsorted variant is compared
/// as a set since its order is unspecified.
///
/// Tests run under fake time so the broadcast timer and its stream delivery are
/// flushed explicitly before each comparison.

int _cmp(DocumentSnapshot<int> a, DocumentSnapshot<int> b) {
  final byValue = a.data.compareTo(b.data);
  return byValue != 0 ? byValue : a.doc.id.compareTo(b.doc.id);
}

List<String> _ordered(List<DocumentSnapshot<int>> snaps) =>
    [for (final s in snaps) '${s.doc.id}=${s.data}'];

List<String> _asSet(List<DocumentSnapshot<int>> snaps) =>
    _ordered(snaps)..sort();

void _reset(FakeAsync async) {
  Loon.unsubscribe();
  // broadcast: false so the reset doesn't schedule a broadcast that could
  // race the next test's observer.
  Loon.clearAll(broadcast: false);
  async.flushMicrotasks();
}

void _walk({
  required FakeAsync async,
  required bool sorted,
  required int seed,
  required int threshold,
  int rounds = 400,
}) {
  _reset(async);

  final r = Random(seed);
  final col = Loon.collection<int>('items');
  bool filter(DocumentSnapshot<int> s) => s.data >= threshold;

  final query = sorted ? col.where(filter).sortBy(_cmp) : col.where(filter);
  final obs = query.observe();

  final emissions = <List<DocumentSnapshot<int>>>[];
  final sub = obs.stream().listen(emissions.add);
  flushBroadcasts(async);

  final present = <String>{};
  for (var round = 0; round < rounds; round++) {
    final opsThisRound = 1 + r.nextInt(3);
    for (var k = 0; k < opsThisRound; k++) {
      if (present.isEmpty || r.nextInt(10) < 7) {
        final id = '${r.nextInt(8)}';
        col.doc(id).createOrUpdate(r.nextInt(10));
        present.add(id);
      } else {
        final id = present.elementAt(r.nextInt(present.length));
        col.doc(id).delete();
        present.remove(id);
      }
    }

    flushBroadcasts(async);

    final oracle =
        (sorted ? col.where(filter).sortBy(_cmp) : col.where(filter)).get();
    final latest = emissions.last;
    final reason =
        'seed=$seed sorted=$sorted threshold=$threshold round=$round';
    if (sorted) {
      expect(_ordered(latest), _ordered(oracle), reason: reason);
    } else {
      expect(_asSet(latest), _asSet(oracle), reason: reason);
    }
  }

  sub.cancel();
  async.flushMicrotasks();
}

void main() {
  tearDown(() {
    Loon.unsubscribe();
    Loon.clearAll(broadcast: false);
  });

  test('Coalesced delete and recreate evicts a cached query result', () {
    fakeAsync((async) {
      _reset(async);

      final col = Loon.collection<int>('items');
      final doc = col.doc('1');
      doc.create(5);
      flushBroadcasts(async);

      final query = col.where((snap) => snap.data >= 4).observe();
      final emissions = <List<DocumentSnapshot<int>>>[];
      final changes = <List<DocumentChangeSnapshot<int>>>[];
      final valueSub = query.stream().listen(emissions.add);
      final changeSub = query.streamChanges().listen(changes.add);
      flushBroadcasts(async);

      expect(_ordered(emissions.last), ['1=5']);

      doc.delete();
      doc.create(0);
      flushBroadcasts(async);

      expect(_ordered(emissions.last), isEmpty);
      expect(changes, [
        [
          DocumentChangeSnapshot<int>(
            doc: doc,
            data: null,
            event: BroadcastEvents.removed,
            prevData: 5,
          ),
        ],
      ]);
      valueSub.cancel();
      changeSub.cancel();
      async.flushMicrotasks();
    });
  });

  group('ObservableQuery equivalence', () {
    // A spread of selectivities: low threshold (most docs pass), middle, and
    // high (most fail), for both sorted and unsorted queries.
    for (final sorted in [true, false]) {
      for (final threshold in [1, 4, 8]) {
        test(
          '${sorted ? 'sorted' : 'unsorted'} query, threshold $threshold '
          'matches a full recompute',
          () {
            fakeAsync((async) {
              _walk(
                async: async,
                sorted: sorted,
                seed: 1000 + threshold,
                threshold: threshold,
              );
            });
          },
        );
      }
    }
  });
}
