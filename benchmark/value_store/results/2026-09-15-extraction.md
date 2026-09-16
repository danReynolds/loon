# Shared iteration and extraction, 2026-09-15

Local macOS arm64 / Dart 3.12.2 / Flutter test JIT. Two independent processes with reversed method order; five warmups and fifteen measured trials per process. Values are prepopulated in 100 collections of 1,000 items. The account scope selects 1,000 stored values; root selects 100,000. Setup and full result-membership checks are outside timing.

## Results

Pooled median milliseconds across 30 samples:

| Values / scope | Current extraction | Lazy iterator toSet | Shared bucket extraction | Shared bucket iterator toSet |
| --- | ---: | ---: | ---: | ---: |
| unique_ints/root | 4.3640 | 6.0125 | 4.2035 | 5.2070 |
| unique_ints/account | 0.0260 | 0.0410 | 0.0270 | 0.0345 |
| identity_entries/root | 10.6655 | 12.9790 | 10.5430 | 11.7270 |
| identity_entries/account | 0.0560 | 0.0730 | 0.0560 | 0.0650 |
| repeated_100_values/root | 1.9690 | 3.2040 | 2.0350 | 2.7760 |
| repeated_100_values/account | 0.0200 | 0.0315 | 0.0200 | 0.0280 |

The simplest `valuesUnder(path).toSet()` wrapper was slower than direct extraction in these runs. The shared bucket implementation retained approximately current extraction performance while removing the need for two independent tree walkers. Small pooled differences are not reliable wins: e.g. unique-integer current medians were 4.537/4.103 ms versus shared-bucket 3.989/4.785 ms. All implementations still allocate and populate a result set. These timings do not isolate the cost of casts, generator/iterator dispatch, or allocations individually.

## Proposed API and implementation

`values([String path = ""])` is a lazy method, returning the selected path value plus all descendants. Omitting path selects the whole store. `extractValues([String path = ""])` returns a fresh deduplicated set. `getChildValues(path)` remains direct children only. Reserve `entries` for path/value pairs.

The private shared helper yields the existing per-node values iterables. `values` delegates with `yield* bucket`; `extractValues` calls `result.addAll(bucket)`. No per-bucket value copies are made, except a singleton for the exact path value where present. ValueRefStore retains its existing extractValues override using precomputed reference keys; it should not be forced to scan every stored occurrence.

The current helpers are proposals using inspect in the profiling folder. This experiment did not change production code. Benchmark shapes cover large buckets and one selected bucket; many tiny buckets, very deep trees, device/release builds and allocation/retained memory are not qualified here. The shared-bucket lazy consumer was checked for order and semantics and measured with toSet; the previous direct aggregation/cleanup suite has not yet been rerun against this proposed shared implementation.

Semantics checks cover own value and descendants, root, nullable values, duplicates, missing paths, and independence of extracted membership after deleting the source subtree. Both tests passed in both final processes; Dart analysis passed for the two new draft files.

## Reproduce

```sh
PROFILE_WARMUPS=5 PROFILE_TRIALS=15 PROFILE_OUTPUT=/tmp/extraction-forward.json flutter test --no-pub benchmark/value_store/extraction_profile_test.dart --concurrency=1 --reporter expanded
PROFILE_ORDER=reverse PROFILE_WARMUPS=5 PROFILE_TRIALS=15 PROFILE_OUTPUT=/tmp/extraction-reverse.json flutter test --no-pub benchmark/value_store/extraction_profile_test.dart --concurrency=1 --reporter expanded
```

[Raw samples, source hashes and test receipts](2026-09-15-extraction.json).
