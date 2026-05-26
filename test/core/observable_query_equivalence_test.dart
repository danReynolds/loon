import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';

/// Equivalence fuzzer for [ObservableQuery].
///
/// An observable query maintains its result incrementally: on each broadcast it
/// inspects only the changed documents and patches a cached result, rather than
/// recomputing from scratch. The property under test is that this incremental
/// result always equals a fresh full recompute of the same query
/// (`Query.get()`), which filters and sorts the whole collection and is the
/// obviously-correct oracle.
///
/// Each test drives one long random walk of create/update/delete operations
/// over a small id/value space — so documents repeatedly cross the filter
/// boundary, exercising the added/removed/modified transitions in
/// `_onBroadcast` — and compares the value most recently emitted on the query's
/// stream against the oracle after every step. A failing case replays from its
/// seed, sorted flag, and threshold.
///
/// A total-order comparator (value then id) keeps the sorted result unambiguous
/// so it can be compared as an ordered list; the unsorted variant is compared
/// as a set since its order is unspecified.
///
/// Notes on determinism: a single long walk is used rather than many short
/// trials because resetting the global store between trials schedules broadcasts
/// that can race the next trial's observer. A 1ms settle (rather than a
/// zero-duration one) guarantees the broadcast's zero-duration timer has fired
/// and its microtask delivery completed before each comparison.

int _cmp(DocumentSnapshot<int> a, DocumentSnapshot<int> b) {
  final byValue = a.data.compareTo(b.data);
  return byValue != 0 ? byValue : a.doc.id.compareTo(b.doc.id);
}

List<String> _ordered(List<DocumentSnapshot<int>> snaps) =>
    [for (final s in snaps) '${s.doc.id}=${s.data}'];

List<String> _asSet(List<DocumentSnapshot<int>> snaps) =>
    _ordered(snaps)..sort();

Future<void> _settle() => Future.delayed(const Duration(milliseconds: 1));

Future<void> _reset() async {
  Loon.unsubscribe();
  // broadcast: false so the reset doesn't schedule a broadcast that could
  // race the next test's observer.
  await Loon.clearAll(broadcast: false);
  await _settle();
}

Future<void> _walk({
  required bool sorted,
  required int seed,
  required int threshold,
  int rounds = 400,
}) async {
  await _reset();

  final r = Random(seed);
  final col = Loon.collection<int>('items');
  bool filter(DocumentSnapshot<int> s) => s.data >= threshold;

  final query = sorted ? col.where(filter).sortBy(_cmp) : col.where(filter);
  final obs = query.observe();

  final emissions = <List<DocumentSnapshot<int>>>[];
  final sub = obs.stream().listen(emissions.add);
  await _settle();

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

    await _settle();

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

  await sub.cancel();
}

void main() {
  tearDown(_reset);

  group('ObservableQuery equivalence', () {
    // A spread of selectivities: low threshold (most docs pass), middle, and
    // high (most fail), for both sorted and unsorted queries.
    for (final sorted in [true, false]) {
      for (final threshold in [1, 4, 8]) {
        test('${sorted ? 'sorted' : 'unsorted'} query, threshold $threshold '
            'matches a full recompute', () async {
          await _walk(sorted: sorted, seed: 1000 + threshold, threshold: threshold);
        });
      }
    }
  });
}
