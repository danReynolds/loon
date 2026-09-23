# Benchmarks

Maintainer tooling for measuring Loon's performance. None of it is published with the package.

| Tool | Measures | Runs in |
| --- | --- | --- |
| [`value_store/run_core.dart`](value_store/run_core.dart) | The value store, and the dependency and broadcast managers, built from any git ref or directory | Dart JIT and native AOT |
| [`loon_benchmark.dart`](loon_benchmark.dart) | The whole library through its public API | `flutter test` (JIT) |

## Compare versions

`run_core.dart` compiles the store (and, for `manager_core`, the managers) from each source into a
standalone program, runs the same workload against every source, and reports pooled medians with the
range of per-process medians.

```sh
# origin/main, HEAD and the working tree, in JIT and AOT.
dart run benchmark/value_store/run_core.dart

# Dependency propagation, dependency updates and writes, in AOT.
dart run benchmark/value_store/run_core.dart --suite manager_core --modes aot

# Chosen sources and operations.
dart run benchmark/value_store/run_core.dart --suite manager_core \
  --source before=git:5efc2e6 --source after=dir:. \
  --filter '^propagation/' --modes aot --passes 3 --trials 9
```

- `store_core`, the default, covers reads, misses, existence checks, child values, ancestor queries,
  writes, overwrites, deletes and extraction. Paths are shallow, deep, or each under a different
  parent, with UUID-like, long, Unicode and underscore-heavy segments. It also covers
  reference-counted stores.
- `manager_core` covers registering and updating dependencies, deleting 20k documents that share one
  dependency or each have their own, propagation to 20k dependents in one or 5,000 collections,
  chains whose writes alternate between collections, and writes without dependents. It uses the
  fixture documents in `manager_fixtures.dart`, so it leaves out persistence, document data and
  observer delivery.
- Results go to `build/value_store_profiles/<timestamp>-core`, or `--out`: `report.md`, raw samples,
  source hashes and command receipts. Result checks run outside the timed interval. `summarize.dart`
  rebuilds a report from a results directory.
- Compare numbers within one run only, and check the load average first. On a busy machine,
  differences under about 10% are not reliable.

## End to end

`loon_benchmark.dart` drives the real library: write and read throughput, observer setup, broadcast
latency, sorted queries, dependency fan-out into a queried collection, dependency shapes (registering,
propagating to and deleting 20k dependents) and sparse updates.

```sh
flutter test benchmark/loon_benchmark.dart
```

It only uses public API, so it runs unchanged on older versions: add a worktree for the ref, copy this
file into its `benchmark/` directory, and run it there. Timings are JIT and vary between runs, so run
each version a few times.

## CI

CI runs the `store_core` workload in `flutter test` and `manager_core` through `run_core.dart`, one
trial each, to check that both still compile and produce correct results. Timings from shared runners
are not recorded.

## Recording a decision

Add an entry to [DECISIONS.md](DECISIONS.md): the question, what was chosen, the numbers that decided
it and how to reproduce them. Don't commit raw results.
