import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:loon/src/store/store.dart';

void main() {
  for (final (name, store) in [
    ('ValueStore', ValueStore<int>()),
    ('ValueRefStore', ValueRefStore<int>()),
  ]) {
    test('$name matches split semantics for Unicode and underscore runs', () {
      final random = Random(42);
      const segments = ['', '_', 'a_', '_b', 'c', '組織💙', '枝🎈'];
      final paths = <String>{
        for (var i = 0; i < 100; i++)
          List.generate(1 + random.nextInt(5),
              (_) => segments[random.nextInt(segments.length)]).join('__'),
      }.toList();
      final model = <String, int>{};

      for (var step = 0; step < 800; step++) {
        final path = paths[random.nextInt(paths.length)];
        if (random.nextInt(4) == 0) {
          store.delete(path);
          final prefix = path.split('__');
          model.removeWhere((key, _) {
            if (path.isEmpty) return true;
            final parts = key.split('__');
            if (parts.length < prefix.length) return false;
            for (var i = 0; i < prefix.length; i++) {
              if (parts[i] != prefix[i]) return false;
            }
            return true;
          });
        } else {
          final value = random.nextInt(5);
          store.write(path, value);
          model[path] = value;
        }

        if (step % 20 != 0 && step != 799) continue;
        // Build an independent tree using String.split, rather than the
        // production parser. Rebuilding also checks pruning and ref counts.
        final expected = <String, dynamic>{};
        for (final entry in model.entries) {
          Map node = expected;
          final parts = entry.key.split('__');
          for (var i = 0; i < parts.length; i++) {
            if (name == 'ValueRefStore') {
              final Map refs = node['__refs'] ??= <int, int>{};
              refs[entry.value] = (refs[entry.value] ?? 0) + 1;
            }
            if (i == parts.length - 1) {
              final Map values = node['__values'] ??= <String, int>{};
              values[parts[i]] = entry.value;
            } else {
              node = node[parts[i]] ??= <String, dynamic>{};
            }
          }
        }
        expect(store.inspect(), expected, reason: '$name step $step');
        for (final path in paths) {
          expect(store.get(path), model[path],
              reason: '$name step $step get($path)');
        }
      }
    });
  }

  test('Reads through the last resolved parent match reads from the root', () {
    // Runs of underscores split differently depending on where a scan starts, so paths that
    // share a prefix don't always share a parent.
    const segments = ['', '_', '__', 'a', 'a_', '_a'];
    final paths = [
      for (final a in segments) ...[
        a,
        for (final b in segments) ...[
          '${a}__$b',
          for (final c in segments) '${a}__${b}__$c',
        ],
      ],
    ];
    final store = ValueStore<int>();
    for (var i = 0; i < paths.length; i++) {
      store.write(paths[i], i);
    }

    final mismatches = <String>[];
    for (final first in paths) {
      for (final second in paths) {
        store.get(first);
        // A new store over the same tree has no last parent.
        final fromRoot = ValueStore<int>(store.inspect()).get(second);
        if (store.get(second) != fromRoot) {
          mismatches.add('get($second) after get($first)');
        }
      }
    }
    expect(mismatches, isEmpty);
  });
}
