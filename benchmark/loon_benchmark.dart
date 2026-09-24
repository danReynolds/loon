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

  test('Write throughput (broadcast on)', () async {
    // Each write also records its broadcast event and looks up its dependents, the
    // bookkeeping skipped above. Timed before the batched broadcast fires.
    for (final n in [1000, 10000, 50000]) {
      await _resetStore();
      final col = Loon.collection<int>('bench');
      final sw = Stopwatch()..start();
      for (var i = 0; i < n; i++) {
        col.doc('doc_$i').create(i, persist: false);
      }
      sw.stop();
      _report('write + event', n, sw.elapsedMicroseconds);
      await Future.delayed(Duration.zero);
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
      'generateFastId': generateFastId,
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
    // registers in the broadcast manager, and computes an initial value.
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

  test('Dependency fan-out vs dependent count', () async {
    // D documents in one collection depend on a single source document, and a query
    // observes that collection. Each source update propagates to every dependent, and
    // the broadcast re-evaluates them in the query.
    const rounds = 20;

    print(
        '\n  dependency fan-out: update source, $rounds rounds, D dependents');
    print('  ${'D dependents'.padRight(14)} ${'µs/update'.padLeft(14)}');

    for (final d in [100, 1000, 10000]) {
      await _resetStore();

      final source = Loon.collection<int>('sources').doc('source');
      source.create(0, persist: false);
      final dependents = Loon.collection<int>(
        'dependents',
        dependenciesBuilder: (_) => {source},
      );
      for (var i = 0; i < d; i++) {
        dependents.doc('doc_$i').create(i, broadcast: false, persist: false);
      }

      final sub = dependents.stream().listen((_) {});
      await Future.delayed(const Duration(milliseconds: 5));

      final sw = Stopwatch()..start();
      for (var r = 0; r < rounds; r++) {
        source.update(r + 1, persist: false);
        await Future.delayed(Duration.zero); // let the broadcast fire
      }
      sw.stop();

      await sub.cancel();

      final perUpdate = sw.elapsedMicroseconds / rounds;
      print(
          '  ${d.toString().padRight(14)} ${perUpdate.toStringAsFixed(1).padLeft(14)}');
    }
  });

  test('Dependency shapes: register, propagate and delete', () async {
    // 20k documents depend on one source: all in one collection, scattered across 5,000
    // subcollections, or in one collection with a summary that depends on all of them and
    // closes a cycle back to the source. Times registering their dependencies, one source
    // update touching all of them, and deleting their parent collection.
    const count = 20000;
    const rounds = 5;

    print('\n  dependency shapes: $count dependents of one source');
    print('  ${'shape'.padRight(14)} ${'register µs/doc'.padLeft(16)} '
        '${'µs/update'.padLeft(12)} ${'delete µs'.padLeft(12)}');

    for (final shape in ['one_collection', 'scattered', 'shared_cycle']) {
      await _resetStore();

      final source = Loon.collection<int>('accounts').doc('source');
      source.create(0, persist: false);
      final groups = Loon.collection('groups');

      final sw = Stopwatch()..start();
      final docs = <Document<int>>[];
      for (var i = 0; i < count; i++) {
        final doc = groups
            .doc('${shape == 'scattered' ? i % 5000 : 0}')
            .subcollection<int>('items', dependenciesBuilder: (_) => {source})
            .doc('$i');
        doc.create(i, broadcast: false, persist: false);
        docs.add(doc);
      }
      sw.stop();
      final register = sw.elapsedMicroseconds / count;

      if (shape == 'shared_cycle') {
        final summary = Loon.collection<int>('summaries',
            dependenciesBuilder: (_) => docs.toSet()).doc('all');
        summary.create(0, broadcast: false, persist: false);
        Loon.collection<int>('accounts', dependenciesBuilder: (_) => {summary})
            .doc('source')
            .update(0, broadcast: false, persist: false);
      }
      await Future.delayed(Duration.zero);

      sw
        ..reset()
        ..start();
      for (var r = 0; r < rounds; r++) {
        source.update(r + 1, persist: false);
        await Future.delayed(Duration.zero); // let the broadcast fire
      }
      sw.stop();
      final perUpdate = sw.elapsedMicroseconds / rounds;

      sw
        ..reset()
        ..start();
      groups.delete();
      await Future.delayed(Duration.zero);
      sw.stop();

      print(
          '  ${shape.padRight(14)} ${register.toStringAsFixed(2).padLeft(16)} '
          '${perUpdate.toStringAsFixed(1).padLeft(12)} '
          '${sw.elapsedMicroseconds.toString().padLeft(12)}');
    }
  });

  test('Sparse updates in a large collection', () async {
    // 1k scattered updates in a 50k-document collection, with and without one dependent
    // per document in a second collection. Times the writes and the broadcast they trigger.
    const count = 50000;
    const updates = 1000;

    print('\n  sparse updates: $updates of $count documents');
    print('  ${'dependents'.padRight(14)} ${'µs/update'.padLeft(14)}');

    for (final withDependents in [false, true]) {
      await _resetStore();

      final sources = Loon.collection<int>('sources');
      final leaves = Loon.collection<int>('leaves',
          dependenciesBuilder: (snap) => {sources.doc('${snap.data}')});
      for (var i = 0; i < count; i++) {
        sources.doc('$i').create(0, broadcast: false, persist: false);
        if (withDependents) {
          leaves.doc('$i').create(i, broadcast: false, persist: false);
        }
      }
      final changed = [
        for (var i = 0; i < updates; i++) sources.doc('${i * 47 % count}')
      ];
      await Future.delayed(Duration.zero);

      final sw = Stopwatch()..start();
      for (final doc in changed) {
        doc.update(1, persist: false);
      }
      await Future.delayed(Duration.zero); // let the broadcast fire
      sw.stop();

      final perUpdate = sw.elapsedMicroseconds / updates;
      print('  ${(withDependents ? 'one each' : 'none').padRight(14)} '
          '${perUpdate.toStringAsFixed(2).padLeft(14)}');
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
