import 'package:loon/loon.dart';
import '../path_cache_draft.dart';
import '../profile_support.dart';

void profilePathCache() {
  final results = ProfileResults();
  const count = 100000;
  const requests = 100000;
  final store = ValueStore<int>();
  final owners = [
    for (var i = 0; i < count; i++)
      PathOwner('orgs__o__teams__t__accounts__a__items__$i')
  ];
  for (var i = 0; i < count; i++) {
    store.write(owners[i].path, i);
  }

  final cases = <String, List<int>>{
    'hot_128': [for (var i = 0; i < requests; i++) i % 128],
    'hot_2048': [for (var i = 0; i < requests; i++) i % 2048],
    'sequential': [for (var i = 0; i < requests; i++) i],
    'five_reads_per_document': [for (var i = 0; i < requests; i++) i ~/ 5],
    'hot_with_churn': [
      for (var i = 0; i < requests; i++) i % 10 == 0 ? 2048 + i ~/ 10 : i % 128
    ],
  };
  for (final entry in cases.entries) {
    final order = profileSetting('PROFILE_ORDER') == 'reverse'
        ? ['recent', 'lru_2m', 'lru_512k', 'owned', 'scanner']
        : ['scanner', 'owned', 'lru_512k', 'lru_2m', 'recent'];
    final expected = entry.value.fold(0, (sum, index) => sum + index);
    for (final method in order) {
      PathPlanCache? cache = switch (method) {
        'lru_512k' => BoundedPathCache(),
        'lru_2m' =>
          BoundedPathCache(maxBytes: 2 * 1024 * 1024, maxEntries: 4096),
        'recent' => RecentPathCache(),
        _ => null,
      };
      void reset() {
        cache?.clear();
        for (final owner in owners) {
          owner.parsed = null;
        }
      }

      int read() {
        var sum = 0;
        for (final index in entry.value) {
          final owner = owners[index];
          final parsed = method == 'owned'
              ? (owner.parsed ??= ParsedStorePath(owner.path))
              : cache?.lookup(owner.path);
          sum += parsed == null
              ? store.get(owner.path)!
              : parsed.read<int>(store.inspect())!;
        }
        return sum;
      }

      for (final cold in [true, false]) {
        reset();
        if (!cold) check(read() == expected, 'cache warmup result');
        final samples = <int>[];
        for (final record in samplePhases()) {
          if (cold) reset();
          final watch = Stopwatch()..start();
          final actual = read();
          watch.stop();
          check(actual == expected, 'path_cache/${entry.key}/$method');
          if (cache is BoundedPathCache) {
            check(
                cache.accountedBytes <= cache.maxBytes &&
                    cache.length <= cache.maxEntries,
                'cache bound');
          }
          if (record) samples.add(watch.elapsedMicroseconds);
        }
        results.add('${entry.key}/$method/${cold ? 'cold' : 'warm'}', samples, {
          'operations': requests,
          'cached_entries': cache?.length ?? 0,
          'accounted_bytes': cache?.accountedBytes ?? 0
        });
      }
      reset();
    }
  }
  results.save();
}
