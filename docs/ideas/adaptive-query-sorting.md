# Adaptive query sorting

- Status: Parked
- Updated: 2026-09-28

## Problem

An observed sorted query can rebuild and sort its entire result when only a few documents change. For example, updating one document in a 10,000-document result still sorts all 10,000 snapshots before delivering the next list.

Avoiding full result construction when there is no value listener is a separate optimization. This idea concerns queries with active value listeners that need a complete, sorted result.

## Proposal

Maintain a private ordered list of snapshots and update its order incrementally. For a few changed documents, find their old positions and replace in place or remove and reinsert. For larger sparse batches, sort the changed subset and merge it with retained rows. Fall back to full sorting for small results, dense batches, or unavailable or invalid ordering state.

The prototype uses reinsertion for at most 16 changed IDs and explores incremental sorting for results of at least 128 rows with at most one-eighth changed IDs. Its broad thresholds are experimental. A possible first implementation would use a narrower gate, such as at least 1,000 rows and at most 16 changed documents; those adoption thresholds have not been separately qualified.

## Evidence

Measured on 2026-09-28 against a snapshot of the current PR #42 work, including its listener guard. This is a comparison with the current full-sort implementation, not a new comparison with `main`.

The full-library experiment used actual Loon writes and broadcast delivery under Flutter test/JIT on local macOS arm64. Scheduling used `fake_async`; elapsed time used a real stopwatch. It used three rotated process runs, two warmups, five measured trials per point, and an identical-build A/A control. Delivered results were checked against full recomputation.

| Result rows / changed documents | Full sort | Prototype |
|---|---:|---:|
| 1,000 / 1 | 0.205 ms | 0.133 ms |
| 10,000 / 1 | 1.632 ms | 0.334 ms |
| 10,000 / 10 | 2.118 ms | 0.780 ms |
| 1,000 / 100 | 0.399 ms | 0.510 ms |
| 10,000 / 10,000 | 12.632 ms | 13.282 ms |

Native AOT measurements of the actual sorting helper with lightweight rows also showed sparse-update gains. For an initially ordered 10,000-row cache, a cheap comparator, and one change, full sorting took 850 microseconds versus 110 microseconds for the prototype, including creation of the public result list. This isolates the algorithm; it is not a full release-mode Flutter application measurement.

Seven sorting tests, including 600 randomized batches, and four dependency regressions passed on native and Chrome. The full core/native run had 254 passes and the same five listener-guard failures present in the baseline; the sorting prototype introduced no additional failure in that run. Static analysis passed. Listener-guard corrections are separate work.

Large sparse workloads showed substantial gains, while some medium and dense workloads regressed. Control variation was material for some cases. Production device latency, allocation pressure across many observers, and application frame impact remain unmeasured.

## Costs and risks

- About 150 additional production lines across the sorting helper and observer integration.
- An additional O(n) private list of snapshot references for each eligible observer. Document data is not duplicated. Public result lists must remain independent so callers cannot corrupt future ordering by mutating a prior emission.
- Comparators can depend on external state. A touched document may coincide with an ordering change across many rows, so the prototype checks retained order and falls back when it is invalid. That check and complete result delivery remain O(n).
- Repeated array reinsertion is expensive as the changed subset grows. A reinsertion-only experiment took hundreds of milliseconds or more for 10,000 changes in 100,000 rows; larger batches need merging or full sorting.
- Equal sort keys, filtering changes, dependency touches, deletion/recreation, reads between writes, and mutation of earlier emitted lists all need to preserve current behavior.
- Sparse wins do not establish a broad win: the full-library experiment regressed for 1,000 rows / 100 changes and some dense batches, despite the full-sort fallback.

## Revisit when

Application profiling shows full sorting is a meaningful cost for active queries with thousands of results and only a few changed documents per broadcast. Keep the existing full-sort path until that workload justifies the complexity.

## Next validation

1. Rebase the prototype onto the then-current query and listener lifecycle code.
2. Measure a narrower sparse-update gate in a complete release-mode application on representative devices, including small and dense workloads as controls.
3. Measure retained memory and allocation/GC costs with realistic numbers of active observers.
4. Require no material regression in fallback workloads and rerun ordering, filtering, dependency, lifecycle, and mutable-result regressions before adoption.

## References

- Current implementation: [ObservableQuery](../../lib/src/observable_query.dart).
- Related work: [PR #42](https://github.com/danReynolds/loon/pull/42).
- Local prototype branch: `codex/incremental-query-sort`; prototype commit `06879c8`; baseline snapshot `785e199`. These commits were not pushed as part of the experiment.
- The prototype commit contains `benchmark/query_sort/README.md`, benchmark runners, and regression tests. Inspect the report with `git show 06879c8:benchmark/query_sort/README.md` while the local commit is available.
- Raw measurements and validation logs are local-only artifacts under `build/sort-prototype/` in the `incremental-query-sort` worktree; they are not tracked. The committed report and runners preserve the method and summarized results.
