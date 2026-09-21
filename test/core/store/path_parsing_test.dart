import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';

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
}
