// ignore_for_file: avoid_print

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';
import 'package:loon/utils/id.dart';

/// Performance harness for Loon's hot paths. Not part of the normal test
/// suite — run explicitly with:
///
///   flutter test benchmark/loon_benchmark.dart
///
/// Each `test` prints a small table to stdout. Numbers are wall-clock on the
/// current machine and only meaningful relative to each other / across runs.
void main() {
  setUp(() async {
    await _resetStore();
  });

  tearDownAll(() async {
    await _resetStore();
  });

  test('Write throughput (broadcast off)', () async {
    for (final n in [1000, 10000, 50000]) {
      await _resetStore();
      final col = Loon.collection<int>('bench');
      final sw = Stopwatch()..start();
      for (var i = 0; i < n; i++) {
        col.doc('doc_$i').create(i, broadcast: false, persist: false);
      }
      sw.stop();
      _report('write create', n, sw.elapsedMicroseconds);
    }
  });

  test('Read throughput (cache hit on get)', () {
    final col = Loon.collection<int>('bench');
    const n = 50000;
    for (var i = 0; i < n; i++) {
      col.doc('doc_$i').create(i, broadcast: false, persist: false);
    }
    for (final reads in [50000, 200000]) {
      final sw = Stopwatch()..start();
      var sink = 0;
      for (var i = 0; i < reads; i++) {
        sink += col.doc('doc_${i % n}').get()!.data;
      }
      sw.stop();
      expect(sink, greaterThan(0));
      _report('doc get', reads, sw.elapsedMicroseconds);
    }
  });

  test('ID generation', () {
    const n = 100000;
    for (final entry in {
      'generateSecureId': generateSecureId,
      'generateProcessLocalId': generateProcessLocalId,
    }.entries) {
      final gen = entry.value;
      final sw = Stopwatch()..start();
      for (var i = 0; i < n; i++) {
        gen();
      }
      sw.stop();
      _report(entry.key, n, sw.elapsedMicroseconds);
    }
  });

  test('Subscription setup throughput', () async {
    // Each observer creation generates an ID, opens two stream controllers,
    // registers in the broadcast manager, and computes an initial value. The
    // ID generator is the part this PR changes.
    const n = 20000;
    final col = Loon.collection<int>('sub');
    for (var i = 0; i < n; i++) {
      col.doc('doc_$i').create(i, broadcast: false, persist: false);
    }

    final subs = <StreamSubscription<DocumentSnapshot<int>?>>[];
    final sw = Stopwatch()..start();
    for (var i = 0; i < n; i++) {
      subs.add(col.doc('doc_$i').observe().stream().listen((_) {}));
    }
    sw.stop();
    _report('observe+listen', n, sw.elapsedMicroseconds);

    for (final s in subs) {
      await s.cancel();
    }
  });

  test('Broadcast latency vs observer count', () async {
    // Holds N idle document observers, then repeatedly writes to a single
    // unrelated document and waits for that document's observer to emit. Every
    // broadcast visits all N observers, so per-cycle cost should grow ~linearly
    // with N if dispatch is O(all observers).
    const rounds = 50;

    print('\n  broadcast: write 1 doc, $rounds rounds, N idle observers');
    print('  ${'N observers'.padRight(14)} ${'µs/broadcast'.padLeft(14)}');

    for (final n in [0, 100, 1000, 5000]) {
      await _resetStore();

      final col = Loon.collection<int>('obs');

      // The document we will repeatedly write to and await.
      final target = col.doc('target');
      target.create(0, persist: false);
      final emissions = <int>[];
      final sub = target.stream().listen((snap) {
        if (snap != null) emissions.add(snap.data);
      });

      // N idle observers on distinct documents that never change.
      final idleSubs = [
        for (var i = 0; i < n; i++)
          col.doc('idle_$i').observe().stream().listen((_) {}),
      ];

      // Let initial subscriptions settle.
      await Future.delayed(const Duration(milliseconds: 5));
      emissions.clear();

      final sw = Stopwatch()..start();
      for (var r = 0; r < rounds; r++) {
        target.update(r + 1);
        await Future.delayed(Duration.zero); // let the broadcast fire
      }
      sw.stop();

      expect(emissions.length, rounds);

      await sub.cancel();
      for (final s in idleSubs) {
        await s.cancel();
      }

      final perBroadcast = sw.elapsedMicroseconds / rounds;
      print(
          '  ${n.toString().padRight(14)} ${perBroadcast.toStringAsFixed(1).padLeft(14)}');
    }
  });

  test('Sorted query rebroadcast vs result-set size', () async {
    // A sorted query over M documents receives a single-document update. The
    // query re-sorts its entire result set on every rebroadcast, so per-update
    // cost should grow ~M log M.
    const rounds = 30;

    print('\n  sorted query: update 1 doc, $rounds rounds, M docs in result');
    print('  ${'M docs'.padRight(14)} ${'µs/update'.padLeft(14)}');

    for (final m in [100, 1000, 10000]) {
      await _resetStore();

      final col = Loon.collection<int>('q');
      for (var i = 0; i < m; i++) {
        col.doc('doc_$i').create(i, broadcast: false, persist: false);
      }

      final query = col.sortBy((a, b) => a.data.compareTo(b.data));
      var emitted = 0;
      final sub = query.stream().listen((_) => emitted++);

      await Future.delayed(const Duration(milliseconds: 5));
      emitted = 0;

      final target = col.doc('doc_0');
      final sw = Stopwatch()..start();
      for (var r = 0; r < rounds; r++) {
        target.update(-(r + 1)); // keep it sorting to the front
        await Future.delayed(Duration.zero);
      }
      sw.stop();

      expect(emitted, rounds);
      await sub.cancel();

      final perUpdate = sw.elapsedMicroseconds / rounds;
      print(
          '  ${m.toString().padRight(14)} ${perUpdate.toStringAsFixed(1).padLeft(14)}');
    }
  });
}

Future<void> _resetStore() async {
  Loon.unsubscribe();
  await Loon.clearAll(broadcast: false);
}

void _report(String name, int ops, int micros) {
  final perOp = micros / ops;
  print('  ${name.padRight(16)} ${ops.toString().padLeft(8)} ops '
      '${(micros / 1000).toStringAsFixed(1).padLeft(9)} ms '
      '${perOp.toStringAsFixed(3).padLeft(9)} µs/op');
}
