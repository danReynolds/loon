# Typed parent lookup — September 21, 2026

[Sources, raw JIT/AOT samples and validation receipts](2026-09-21-typed-lookup.json)

This records the parent-helper cleanup. The subsequent [shared-getter
comparison](2026-09-21-shared-get.md) also removes the dedicated exact-read loop.

## Implementation

Replace the access-mode enum and `Object? _lookup(path, mode)` with one
`(Map, String)? _getParent(path)` helper. The helper only resolves the owning
node and final segment. Node lookup and path existence perform their own final
map access; extraction continues to use the same parent/segment pair.

This removes the mode switch, result casts and enum, with 18 fewer production
lines overall. Incremental parsing, the dedicated exact getter, storage shape,
public APIs, propagation and mutation behavior are unchanged. The raw `Map`
representation of tree nodes is unchanged; this makes the helper's result type
explicit rather than introducing a new node representation.

The profiling controls support both helper layouts so saved historical libraries
can still be used as inputs.

Retain the typed helper for its simpler contract and smaller implementation,
accepting the modest isolated lookup cost. This is a maintainability trade-off,
not a claim of faster engine workloads or identical performance.

## Measurement scope

The baseline is commit `b325931`. Three fresh processes per implementation and
runtime, nine measured samples per operation, five warmups and a minimum 200 ms
warmup phase. Order alternates across passes. Standalone Dart store measurements
and headless Flutter measurements are separate series; absolute times must not
be compared across hosts. All builds and correctness checks finish before Flutter
timings begin. Result checks remain active in release builds.

In the standalone AOT series, shallow collection lookup rose from 3.500 to
3.737 ms per 100k calls, shallow value-existence checks from 6.292 to 6.780 ms,
and deep node-existence checks from 17.295 to 18.158 ms. Deep collection lookup
was 18.909 versus 19.096 ms. This cleanup has a small measured lookup cost;
it is not a performance optimization. JIT changes on these paths were smaller.
Unchanged mutation controls also moved, so the timings do not isolate allocation
or code-generation causes.

## Validation and limits

253 native/core/benchmark tests and 72 headless Chrome tests passed; static
analysis is clean. All 21 profiling variants configure and parse. The affected
baseline and identity controls each pass 136 core tests. Existing tests cover
null values, empty segments, unusual underscore boundaries, random mutations,
subtree extraction and reference counts.

The Flutter series encountered substantial host-load changes, including a
one-minute load average above 80 after builds and above 110 during timing.
The complete process ranges and raw samples are retained. These results cannot
establish small engine-level performance differences. Measurements are macOS
arm64 / Dart 3.12.2 / Flutter 3.44.4, not physical mobile-device evidence.

## Headless Flutter results

Values below are pooled medians in milliseconds per named batch. The archive
also contains the per-process medians and ranges.

Large apparent improvements in the Flutter table also affect unchanged exact
reads and mutation paths. They are not attributed to this refactor. The
standalone measurements provide the clearer signal for its small lookup cost;
the full-engine run is exploratory evidence under substantial contention.
## aot

| Operation | Committed implementation | Typed parent helper |
| --- | ---: | ---: |
| 100k shallow value-existence checks | 7.294 | 8.544 |
| 100k deep node-existence checks | 18.419 | 18.404 |
| 100k shallow collection lookups | 4.300 | 4.413 |
| 100k deep collection lookups | 26.689 | 19.927 |
| 20k deep single-value extractions | 6.635 | 6.287 |
| 20k deep exact reads | 5.128 | 4.776 |
| Notify 100k shared dependents | 25.857 | 21.184 |
| Notify 20k nested dependents | 3.912 | 3.195 |
| Notify 10k dependents with four queries | 28.885 | 19.674 |
| Delete 100k shared dependents | 28.621 | 19.928 |
| 1k writes without dependents | 0.987 | 1.039 |
| 1k writes with one dependent each | 3.655 | 2.254 |

## jit

| Operation | Committed implementation | Typed parent helper |
| --- | ---: | ---: |
| 100k shallow value-existence checks | 7.295 | 7.154 |
| 100k deep node-existence checks | 20.009 | 18.948 |
| 100k shallow collection lookups | 3.684 | 3.901 |
| 100k deep collection lookups | 19.878 | 20.301 |
| 20k deep single-value extractions | 8.171 | 6.919 |
| 20k deep exact reads | 6.340 | 5.254 |
| Notify 100k shared dependents | 19.154 | 16.767 |
| Notify 20k nested dependents | 3.741 | 3.944 |
| Notify 10k dependents with four queries | 19.879 | 18.911 |
| Delete 100k shared dependents | 18.528 | 17.801 |
| 1k writes without dependents | 1.124 | 1.194 |
| 1k writes with one dependent each | 2.388 | 2.913 |
