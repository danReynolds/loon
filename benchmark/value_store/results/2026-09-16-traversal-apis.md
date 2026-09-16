# Traversal API comparison — September 16, 2026

[Raw samples, source/build hashes and command receipts](2026-09-16-traversal-apis.json)
accompany this report. All implementations remain benchmark prototypes; no new
production traversal API or extraction change was adopted in this run.

## Findings

The typed callback remains a strong general-purpose baseline in release AOT.
There is no consistent winner across operations and tree shapes:

- The hand-written iterator reduces the 100k bucketed sum time by 27% versus
  the recursive generator, but takes 20% longer than the typed callback. It is
  useful if an Iterable API is desired, rather than a universal speed upgrade.
- Direct buckets help bulk list export: 2.39 ms versus 2.95 ms for the typed
  callback on 100k bucketed values, and 1.71 ms versus 2.69 ms for one flat bucket.
  Export timings vary across processes. The existing recursive bucket generator
  performs poorly on singleton/deep shapes, so this is an operation-specific win.
- Specialized walkers save only about 3% on the bucketed sum versus the typed
  callback. Cleanup and union show no compelling consistent benefit to justify
  duplicating traversal for each operation. Small differences need a quieter host
  before being treated as reliable gains.

JIT rewards some alternatives much more than AOT; production choices should use
the release results. Avoiding eager extraction is the larger cleanup improvement:
the typed callback takes 16.06 ms versus 22.23 ms for extraction on the flat case.
This does not make extraction unnecessary when callers actually need a distinct,
materialized set.

## Implementations and comparison boundaries

- `callback`: the original generic per-value callback walker.
- `typedCallback`: typed value buckets and leaf skipping, retaining a generic
  callback. Its child traversal matches the specialized walkers' navigation.
- `generator`: the existing recursive `sync*` / `yield*` value iterator.
- `iterator`: a hand-written, restartable Iterable/Iterator with an explicit DFS
  stack, one active bucket iterator and no recursive generator machinery.
- `buckets`: the existing bucket generator consumed directly with nested loops,
  or `List.addAll` for export. It hands over existing buckets without copying.
- `specialized`: operation-specific sum, export, cleanup and union walkers. They
  have no arbitrary per-value callback. Export uses each bucket's `addAll`.
- `extraction`: current `extractValues`, followed by the requested processing.

The new implementations are in [traversal_api_draft.dart](../traversal_api_draft.dart)
and their consumers are in [workloads/traversal_apis.dart](../workloads/traversal_apis.dart).
These compare concrete implementations, not solely the cost of one function call.
Iterator bookkeeping, typed access, bulk operations and compiler optimization all
contribute. Specialized walkers duplicate traversal code and are controls for the
potential benefit of integrating the operation, not automatically desirable APIs.

Each sum consumer has its own lexical scope. Ordinary loops do not share a
captured accumulator with the callback branch, avoiding a potential confound in
the older combined consumer. Cleanup likewise isolates callback captures. Export
now measures only list construction, with order/membership checks outside timing;
the older iterable workload also folded the exported list inside its interval.
Compare implementations within this report rather than attributing differences
between reports entirely to the API shape.

All timed sum/export values are unique, keeping eager set extraction semantically
comparable. Separate tests cover duplicates and nulls. Cleanup uses actual
Document keys and ValueStores, including a selected path's own entry, descendants,
shared sources, multiple dependencies, pruning and a survivor. It remains an
isolated model rather than the full Loon deletion/broadcast path.

## Native release AOT

Pooled median milliseconds; per-process medians and every sample are in the JSON.

| Operation | callback | typedCallback | generator | iterator | buckets | specialized | extraction |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| sum/buckets_100k | 1.363 | 1.334 | 2.193 | 1.597 | 1.340 | 1.292 | 4.090 |
| sum/flat_100k | 1.347 | 1.315 | 2.118 | 1.559 | 1.291 | 1.292 | 4.150 |
| sum/singletons_20k | 1.895 | 1.382 | 4.797 | 1.421 | 4.284 | 1.311 | 3.045 |
| sum/deep_10k | 3.560 | 3.199 | 8.877 | 4.488 | 8.725 | 3.042 | 4.720 |
| sum/scoped_1k_x100 | 1.377 | 1.339 | 2.180 | 1.613 | 1.353 | 1.325 | 2.972 |
| export/buckets_100k | 3.160 | 2.954 | 3.861 | 3.558 | 2.392 | 2.650 | 5.533 |
| export/flat_100k | 2.838 | 2.691 | 3.780 | 3.252 | 1.708 | 1.677 | 5.602 |
| export/singletons_20k | 2.183 | 1.631 | 5.139 | 1.787 | 4.715 | 1.816 | 3.268 |
| export/deep_10k | 3.679 | 3.361 | 9.223 | 4.630 | 8.959 | 3.577 | 4.918 |
| cleanup/flat_100k | 16.375 | 16.055 | 17.015 | 16.221 | 15.607 | 15.573 | 22.230 |
| cleanup/nested_10k_two_dependencies | 2.865 | 2.846 | 2.946 | 2.943 | 2.877 | 2.860 | 3.417 |
| union/100k_10k_sets | 12.778 | 12.243 | 12.652 | 12.283 | 12.339 | 12.648 | 13.021 |

`scoped_1k_x100` is the total for 100 complete subtree queries, each visiting
1,000 values. Other sum/export rows perform one subtree query. `buckets_100k`
contains 100 large value buckets; `flat_100k` contains one. Singleton/deep shapes
stress many small tree nodes instead. Union processes 10,000 overlapping sets
into 100,000 distinct Document references.

## Native JIT

| Operation | callback | typedCallback | generator | iterator | buckets | specialized | extraction |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| sum/buckets_100k | 0.877 | 0.712 | 0.807 | 0.636 | 0.331 | 0.301 | 3.995 |
| sum/flat_100k | 0.864 | 0.707 | 0.780 | 0.634 | 0.293 | 0.291 | 3.954 |
| sum/singletons_20k | 2.204 | 1.518 | 5.058 | 1.413 | 4.654 | 1.558 | 3.020 |
| sum/deep_10k | 4.558 | 4.162 | 10.173 | 4.240 | 9.982 | 4.045 | 3.606 |
| sum/scoped_1k_x100 | 0.896 | 0.729 | 0.821 | 0.652 | 0.351 | 0.322 | 2.893 |
| export/buckets_100k | 1.757 | 1.621 | 1.764 | 1.562 | 1.214 | 1.194 | 4.298 |
| export/flat_100k | 1.687 | 1.583 | 1.671 | 1.568 | 0.781 | 0.781 | 4.309 |
| export/singletons_20k | 2.567 | 1.894 | 5.236 | 1.720 | 5.205 | 1.810 | 3.401 |
| export/deep_10k | 4.843 | 4.215 | 10.444 | 4.405 | 10.441 | 2.761 | 3.755 |
| cleanup/flat_100k | 16.300 | 16.302 | 16.622 | 16.415 | 15.960 | 15.867 | 26.134 |
| cleanup/nested_10k_two_dependencies | 2.985 | 3.018 | 3.013 | 3.016 | 2.982 | 2.881 | 3.662 |
| union/100k_10k_sets | 15.392 | 14.989 | 15.237 | 15.207 | 15.850 | 15.098 | 15.927 |

## Loop syntax control

These compare concrete SDK List/Map implementations and a cheap integer sum.
They do not establish a language-wide ranking of `forEach` and `for-in`.

| Loop over 100k elements | JIT ms | AOT ms |
| --- | ---: | ---: |
| list_for_in | 0.251 | 0.064 |
| list_for_each | 0.536 | 0.064 |
| map_keys_lookup | 2.539 | 2.050 |
| map_entries | 0.569 | 0.662 |
| map_values | 0.298 | 0.427 |
| map_for_each | 0.577 | 0.287 |

The JIT list `for-in` control is bimodal across processes: medians were 0.432,
0.080, 0.422 and 0.086 ms. Its pooled median is not a stable single-process cost,
so do not infer an exact JIT syntax speed ratio from that row. The AOT list loops
are effectively tied.

The keys-plus-lookup loop repeats a map lookup for each element. `Map.forEach`
supplies both key and value directly; the entries and values loops also avoid the
extra keyed lookup. The earlier extraction proposal additionally skipped leaves,
so its combined improvement cannot be assigned solely to replacing loop syntax.

## Reproduction and validation

```sh
dart run benchmark/value_store/run.dart \
  --out build/value_store_profiles/20260916-traversal-apis \
  --variants combined --suites traversal_apis \
  --passes 4 --trials 15 --warmups 8 --warmup-ms 500
```

Use a fresh output directory for a repeat. Flutter 3.44.4 / Dart 3.12.2, macOS
arm64. Two modes × four independent processes = **eight native timing processes**.
There are 90 operation rows per process and **60 measured samples per operation
per runtime**. Warmup requires at least eight iterations and 500 ms of phase time
including preparation/checks. Method order reverses on alternate process passes.

All builds and 141 correctness checks finished before native timing. Tests cover
nullable and duplicate values, traversal order, fresh and independent iterators,
early stopping, first-advance prefix lookup, a 4,000-level iterator traversal,
random write/delete sequences, selected-path values, reverse cleanup and union
membership. Result checks stay enabled in release. Analyzer and diff checks pass.

Other work was active on the host, and load averages were recorded. Interpret
small differences cautiously and use per-process ranges; they are not confidence
intervals. This is desktop steady-state timing, not mobile-device qualification
or an allocation/retained-heap profile. No cross-runtime pooling is performed.
