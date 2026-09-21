import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';
import 'path_cache_draft.dart';

void main() {
  test('Cached paths preserve split boundaries and immutable segments', () {
    for (final path in [
      '',
      'a___b',
      '__leading',
      'trailing__',
      'a____b',
      '組織💙___枝🎈'
    ]) {
      final parsed = ParsedStorePath(path);
      expect(parsed.segments, path.split('__'));
      expect(() => parsed.segments.add('mutate'), throwsUnsupportedError);
      final store = ValueStore<int>()..write(path, 1);
      expect(parsed.read<int>(store.inspect()), 1);
      store.delete(path);
      expect(parsed.read<int>(store.inspect()), isNull);
      store.write(path, 2);
      expect(parsed.read<int>(store.inspect()), 2);
      store.clear();
      expect(parsed.read<int>(store.inspect()), isNull);
      store.graft(ValueStore<int>()..write(path, 3));
      expect(parsed.read<int>(store.inspect()), 3);
    }
  });

  test('Bounded cache evicts least recently used metadata and resets', () {
    final cache = BoundedPathCache(maxEntries: 2);
    final a = cache.lookup('a');
    final b = cache.lookup('b');
    expect(cache.lookup('a'), same(a));
    cache.lookup('c');
    expect(cache.length, 2);
    expect(cache.lookup('b'), isNot(same(b)));
    cache.clear();
    expect(cache.length, 0);
    expect(cache.accountedBytes, 0);
  });

  test('Byte budget and maximum key length also bound admission', () {
    final cache = BoundedPathCache(maxBytes: 1024);
    for (var i = 0; i < 10000; i++) {
      cache.lookup('orgs__${i}__items__0');
      expect(cache.accountedBytes, lessThanOrEqualTo(1024));
    }
    expect(cache.lookup('x' * 513), isNull);
    expect(cache.accountedBytes, lessThanOrEqualTo(1024));
    expect(BoundedPathCache(maxBytes: 1).lookup('a'), isNull);
  });

  test('Recent cache admits consecutive reuse and releases on replacement', () {
    final cache = RecentPathCache();
    expect(cache.lookup('a'), isNull);
    final a = cache.lookup('a');
    expect(a, isNotNull);
    expect(cache.lookup('a'), same(a));
    expect(cache.lookup('b'), isNull);
    expect(cache.length, 1);
    expect(cache.lookup('a'), isNull);
    expect(cache.lookup('x' * 513), isNull);
    expect(cache.length, 0);
    expect(cache.accountedBytes, 0);
  });
}
