import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';

/// Model-based property tests for the path-keyed store structures.
///
/// Each test drives randomized operation sequences against the real store and
/// a trivial reference model, then asserts the two agree (and that structural
/// invariants like "empties out completely" hold). The reference results are
/// recomputed from scratch each step, so they're an independent oracle for the
/// stores' incremental bookkeeping. On failure the seed and operation log are
/// printed so the case can be replayed.
///
/// A small segment/value alphabet is used deliberately to force path collisions
/// and shared prefixes, which is where the tree-restructuring edge cases live.
///
/// Scope: covers `write` and recursive `delete`. Non-recursive `delete` has
/// subtler semantics (it prunes a node's immediate values while keeping deeper
/// descendants) and is left for a dedicated model.
const _d = '__';
const _alphabet = ['a', 'b', 'c'];

String _randomPath(Random r) {
  final depth = 1 + r.nextInt(3); // 1..3 segments
  return List.generate(depth, (_) => _alphabet[r.nextInt(_alphabet.length)])
      .join(_d);
}

/// All non-empty paths of depth 1 and 2 — a fixed grid of query points.
final _grid = <String>[
  for (final a in _alphabet) ...[
    a,
    for (final b in _alphabet) '$a$_d$b',
  ],
];

/// Whether [key] is at or below [path] in the tree.
bool _atOrUnder(String key, String path) =>
    path.isEmpty || key == path || key.startsWith('$path$_d');

String _parent(String path) {
  final i = path.lastIndexOf(_d);
  return i == -1 ? '' : path.substring(0, i);
}

String _lastSegment(String path) {
  final i = path.lastIndexOf(_d);
  return i == -1 ? path : path.substring(i + _d.length);
}

void main() {
  group('PathRefStore property', () {
    test('matches reference model across random inc/dec sequences', () {
      for (var seed = 0; seed < 200; seed++) {
        final r = Random(seed);
        final store = PathRefStore();
        final live = <String>[]; // inc'd paths, with multiplicity
        final ops = <String>[];

        for (var step = 0; step < 50; step++) {
          // dec only targets paths that were actually inc'd, mirroring how the
          // library pairs inc/dec; bias toward inc when nothing is live.
          if (live.isEmpty || r.nextBool()) {
            final p = _randomPath(r);
            store.inc(p);
            live.add(p);
            ops.add('inc($p)');
          } else {
            final p = live.removeAt(r.nextInt(live.length));
            store.dec(p);
            ops.add('dec($p)');
          }

          final reason = 'seed=$seed ops=$ops';
          for (final q in {..._grid, ...live}) {
            // has(q): true iff some live path is q or a descendant of q.
            final expected = live.any((p) => _atOrUnder(p, q));
            expect(store.has(q), expected, reason: '$reason has($q)');
          }
          expect(store.isEmpty, live.isEmpty, reason: '$reason isEmpty');
        }
      }
    });
  });

  group('ValueStore property', () {
    test('matches reference model across random write/delete sequences', () {
      for (var seed = 0; seed < 200; seed++) {
        final r = Random(seed);
        final store = ValueStore<int>();
        final model = <String, int>{};
        final ops = <String>[];
        var counter = 0;

        for (var step = 0; step < 50; step++) {
          if (r.nextInt(3) != 0) {
            final p = _randomPath(r);
            final v = counter++;
            store.write(p, v);
            model[p] = v;
            ops.add('write($p,$v)');
          } else {
            final p = _randomPath(r);
            store.delete(p); // recursive
            model.removeWhere((k, _) => _atOrUnder(k, p));
            ops.add('delete($p)');
          }

          final reason = 'seed=$seed ops=$ops';
          for (final q in {..._grid, ...model.keys}) {
            expect(store.get(q), model[q], reason: '$reason get($q)');
            expect(store.hasValue(q), model.containsKey(q),
                reason: '$reason hasValue($q)');
            final hasPath = model.containsKey(q) ||
                model.keys.any((k) => k.startsWith('$q$_d'));
            expect(store.hasPath(q), hasPath, reason: '$reason hasPath($q)');
          }
          for (final q in _grid) {
            final expected = <String, int>{};
            for (final entry in model.entries) {
              if (_parent(entry.key) == q) {
                expected[_lastSegment(entry.key)] = entry.value;
              }
            }
            final actual = store.getChildValues(q) ?? const <String, int>{};
            expect(actual, equals(expected),
                reason: '$reason getChildValues($q)');
          }
          expect(store.isEmpty, model.isEmpty, reason: '$reason isEmpty');
        }
      }
    });
  });

  group('ValueRefStore property', () {
    test('ref aggregation matches the values in each subtree', () {
      for (var seed = 0; seed < 200; seed++) {
        final r = Random(seed);
        final store = ValueRefStore<String>();
        final model = <String, String>{};
        final ops = <String>[];

        // getRefs(path) aggregates values strictly under a node; for the root
        // path it aggregates every value in the store.
        Map<String, int> refsUnder(String path) {
          final counts = <String, int>{};
          for (final entry in model.entries) {
            final under =
                path.isEmpty ? true : entry.key.startsWith('$path$_d');
            if (under) {
              counts[entry.value] = (counts[entry.value] ?? 0) + 1;
            }
          }
          return counts;
        }

        for (var step = 0; step < 50; step++) {
          if (r.nextInt(3) != 0) {
            final p = _randomPath(r);
            // Small value space → many shared refs to stress the aggregation.
            final v = _alphabet[r.nextInt(_alphabet.length)];
            store.write(p, v);
            model[p] = v;
            ops.add('write($p,$v)');
          } else {
            final p = _randomPath(r);
            store.delete(p); // recursive
            model.removeWhere((k, _) => _atOrUnder(k, p));
            ops.add('delete($p)');
          }

          final reason = 'seed=$seed ops=$ops';
          for (final q in ['', ..._grid]) {
            final expected = refsUnder(q);
            final actual = store.getRefs(q) ?? const <String, int>{};
            expect(Map<String, int>.from(actual), equals(expected),
                reason: '$reason getRefs("$q")');
            expect(store.extractValues(q), equals(expected.keys.toSet()),
                reason: '$reason extractValues("$q")');
          }
        }
      }
    });
  });
}
