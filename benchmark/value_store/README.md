# ValueStore performance workflow

Optimize for **time to insight during iteration**. Start with the smallest check
that answers the question; reserve the full validation matrix for the settled PR.

1. Make a small change and run the tests directly affected by it. Reuse existing
   regression tests rather than rerunning the entire suite after each edit.
2. If performance is relevant, run a short comparison of the affected operation.
   For store-only changes, prefer standalone Dart AOT through `run_core.dart` to
   rebuilding Flutter hosts. A one-process screen can reject a clearly poor idea;
   it cannot establish a small performance difference.
3. Repeat promising candidates or investigate a specific regression. Add JIT or
   complete engine workloads when they answer an unresolved question. Avoid
   rebuilding the full Flutter matrix for routine helper refactors.
4. Once the PR is settled, run the full correctness suite, analysis, and relevant
   repeated JIT/AOT comparisons in the real headless Flutter host. Record source
   hashes and measured trade-offs before committing to performance claims.

Use **native AOT results to choose production optimizations**. JIT is a separate
comparison, useful for development and diagnosis; a JIT win does not establish an
AOT win. Host contention or a noisy small difference is a reason to limit the
conclusion, not automatically launch another broad run.

The engine workloads in `workloads/` run unchanged through either the small
`*_profile_test.dart` wrappers or `native_main.dart` in a real Flutter application.
The native host imports the actual Loon library. It does not substitute a Dart-only
copy of the store or mock Flutter to make AOT compilation work.

The macOS runner is **headless**: it starts a Flutter engine without a window or
view, runs as a background-only process, and prohibits activation. It does not
take keyboard focus or create a Dock icon. Results explicitly record headless
execution. Historical windowed hosts must be rebuilt; compare candidates within
the same host setup rather than mixing old windowed and new headless timings.

For quick store-algorithm experiments, `run_core.dart` additionally isolates the
actual store source files in a standalone Dart library. This avoids Flutter builds
between candidates. It is a separate measurement series; verify selected changes
with the full Flutter runner before drawing engine-level conclusions.

First paired native run: [results and interpretation](results/2026-09-15-native.md),
with [raw samples and receipts](results/2026-09-15-native.json).

Dart-only runner and extraction follow-up:
[cost breakdown and interpretation](results/2026-09-16-extraction.md),
with [raw samples and receipts](results/2026-09-16-extraction.json).

Hand-written iterator, direct buckets and specialized walkers:
[comparison and interpretation](results/2026-09-16-traversal-apis.md),
with [raw samples and receipts](results/2026-09-16-traversal-apis.json).

Document allocation changes and retained dependency entries:
[timing and live-heap comparison](results/2026-09-16-document-entries.md),
with [raw samples and receipts](results/2026-09-16-document-entries.json).

Core store comparison against main, the committed PR and the incoming refactor:
[results and implementation decisions](results/2026-09-20-store-core.md),
with [source snapshots, raw samples and receipts](results/2026-09-20-store-core.json).

Delimiter-scanning follow-up, including long IDs, Unicode and complete dependency
workloads: [results and changes versus main](results/2026-09-20-path-scanning.md),
with [source snapshots, raw samples and receipts](results/2026-09-20-path-scanning.json).

Parsed-path ownership, bounded caches and cleanup:
[memory and timing experiments](results/2026-09-20-path-cache.md),
with [source snapshots, raw samples and heap captures](results/2026-09-20-path-cache.json).

Operation-local dependency traversal:
[complexity trade-offs and results](results/2026-09-20-scoped-traversal.md),
with [source snapshots, raw samples and receipts](results/2026-09-20-scoped-traversal.json).

Shared helper cleanup and headless execution:
[implementation trade-offs and results](results/2026-09-21-scoped-cleanup.md),
with [source snapshots, headless focus checks and timings](results/2026-09-21-scoped-cleanup.json).

Typed parent lookup cleanup:
[implementation and measured trade-offs](results/2026-09-21-typed-lookup.md),
with [source snapshots and JIT/AOT samples](results/2026-09-21-typed-lookup.json).

Shared typed getter, using the focused operation filter:
[decision and results](results/2026-09-21-shared-get.md),
with [source snapshots and samples](results/2026-09-21-shared-get.json).

Pruning, reference counts, dependency updates and collection-map helpers:
[cleanup decisions and focused timings](results/2026-09-21-elegance.md),
with [sources, samples and receipts](results/2026-09-21-elegance.json).

## Compare exact store versions

```sh
# main, the committed PR, and the current working tree; JIT and native Dart AOT.
dart run benchmark/value_store/run_core.dart

# Focused iteration: read hits/misses only, without rebuilding Flutter hosts.
dart run benchmark/value_store/run_core.dart \
  --source committed=git:HEAD --source candidate=dir:. \
  --filter '(^empty/get$|/(get|get_early_miss|get_late_miss)$)' \
  --passes 2 --trials 7 --warmups 3 --warmup-ms 80

# Pin any baseline and compare a separate checkout or source snapshot.
dart run benchmark/value_store/run_core.dart \
  --source main=git:origin/main \
  --source previous=git:d18a5e4 \
  --source candidate=dir:. \
  --passes 3 --trials 11 --warmups 5 --warmup-ms 200

# Screen manager algorithms without building Flutter hosts. This standalone-only
# suite uses fixture handles and cannot establish whole-engine performance.
dart run benchmark/value_store/run_core.dart --suite manager_core \
  --source before=dir:/path/to/saved/package --source candidate=dir:. \
  --modes aot --passes 2 --trials 7 --warmups 3 --warmup-ms 80

# Confirm a candidate against a saved package's store files in real Flutter hosts.
dart run benchmark/value_store/run.dart \
  --store-baseline /path/to/saved/package \
  --variants store_before,combined --suites store_core,dependency,extraction_cost
```

The core runner preserves the selected source text and hashes in its manifest,
resolves Git refs to commits, builds every AOT candidate before timing, reverses
process order on alternate passes, and records raw samples and command receipts.
Only the store files' `part of` directives change for standalone compilation;
`Json` keeps its existing alias. The measurement helper gets compilation-mode
constants in place of its Flutter import. Production method bodies are unchanged.
Result checks remain enabled in AOT and run outside the timed interval.
`--filter` selects `store_core` or `manager_core` operation names by regular expression and is
recorded in the manifest. Unselected operations are not timed; shared fixture
construction still runs. Short filtered runs are exploratory screens, not the
full validation required when the PR is settled.

`manager_core` additionally freezes the actual dependency and broadcast manager
methods, snapshots and set-flattening extension. Its generated workload uses
explicit fixture document/observer types from `manager_fixtures.dart`; it copies
the document path/hash/equality behavior and Flutter's set comparison. It omits
persistence, stored document data and real observer delivery. It covers 200
updates in a 20k-document dependency graph and propagation across one or 5,000
collections, with empty/existing event maps and cached observer values. Use it
to screen these algorithms, then validate semantics against the real Loon tests.

The Flutter `store_before` variant overlays only the three store files and
`lib/utils/store.dart` from `--store-baseline`. The rest of Loon is identical to
`combined`, isolating store costs in real dependency workloads. It does not claim
to compare the entire historical library. The directory must contain those files;
the manifest records the resulting full-library hashes.

## Parsed-path experiments

```sh
# Cold admission, warm reuse, scan churn and mixed access; standalone JIT/AOT.
dart run benchmark/value_store/run_core.dart --suite path_cache \
  --source current=dir:. --out build/path-cache-core

# Separate diagnostic process: seed 100k handles, parse, delete stored values,
# release handles, then clear the cache. Uses the frozen candidate above.
dart run benchmark/value_store/run_path_cache_retention.dart build/path-cache-core/current

# Confirm cache costs in complete Flutter release dependency workloads.
dart run benchmark/value_store/run.dart \
  --variants combined,path_cache_lru,path_cache_recent --modes aot \
  --suites lookup,store_core,dependency --out build/path-cache-flutter
```

These caches exist only in benchmark drafts/disposable variant copies. The LRU
uses an estimated byte budget plus entry and key-length limits; this is not a
strict VM heap bound. The recent-path alternative admits the second consecutive
read and retains one key/plan. Both cache immutable path components, never store
nodes or document values. The full-engine variants share one cache across stores
and clear it on engine reset. The owner prototype measures optional parsed
metadata on synthetic handles; it does not include the cost of adding a field to
every real Document. Retention is a separate JIT VM-service diagnostic, not AOT
RSS or a dominator-size measurement. GC is requested for diagnostics only.

## Default comparison: JIT and release AOT

On macOS with Flutter, Xcode and CocoaPods installed, resolve the root package
normally first, then run:

```sh
dart run benchmark/value_store/run.dart
```

The runner builds isolated Flutter hosts under ignored
`build/value_store_profiles/<run>/`, then runs fresh processes sequentially:

- `jit`: Flutter debug, with JIT compilation and debug assertions.
- `aot`: Flutter release, with native ahead-of-time compilation.
- `profile`: optional instrumented AOT for DevTools investigations.

The default compares `baseline,combined` in `jit,aot`, across all eleven workload
suites. It uses at least five warmup iterations and 250 ms of warmup phase time,
then fifteen measured trials per operation, in two independent processes. Job
order and iterable/extraction/extraction-cost/traversal-API method order are reversed for the second
pass. Warmup phase
time includes fixture preparation/checks; it is a practical minimum, not a proof
that every JIT function reached its final optimization tier. Increase warmup or
repetition if process medians disagree. Small microsecond measurements need
particular care.

All builds and core/semantics checks finish before native timings begin. Fixture
setup and correctness checks are outside timed intervals; benchmark-specific
registration/setup metrics are explicitly named. Correctness uses exceptions,
not Dart `assert`, so it remains enforced in release builds. Each binary checks
its actual Flutter compilation mode before producing a result.

Hosted dependency versions are pinned to the root `pubspec.lock`; the product
package and example application are not modified. The generated desktop host
alone disables app sandboxing to write its result files to the chosen directory.
Run on an otherwise idle machine; load averages are recorded, not automatically
interpreted as proof that the host was idle.

Focused comparisons:

```sh
# API experiments against the current library, in both runtimes.
dart run benchmark/value_store/run.dart --variants combined --suites iterable,extraction,extraction_cost

# Callback, hand-written iterator, bucket iteration and specialized walkers.
dart run benchmark/value_store/run.dart --variants combined --suites traversal_apis

# Registration, sparse fan-out, query delivery and cleanup.
dart run benchmark/value_store/run.dart --variants baseline,combined --suites dependency

# One selected dependency topology.
dart run benchmark/value_store/run.dart --variants combined,touch --suites dependency --case 100k_shared

# Four small allocation changes, crossed with entry versus reconstructed handles.
dart run benchmark/value_store/run.dart --variants document_before,document_before_paths,combined,document_paths --suites documents,dependency --passes 3 --trials 11 --warmups 5 --warmup-ms 500

# Separate instrumented AOT heap evidence; no heap data enters timing tables.
dart run benchmark/value_store/run.dart --out build/value_store_profiles/document-heap --variants combined,document_paths --suites documents --modes profile --build-only
dart run benchmark/value_store/run_retention.dart build/value_store_profiles/document-heap
```

`--modes`, `--variants`, `--suites`, `--out`, `--passes`, `--trials`, `--warmups` and
`--warmup-ms` configure a run. `--out` must not already exist. `--skip-validation`
is for exploration only and is explicitly marked in the manifest/report.

The runner automatically produces `report.md` and `raw-results.json`. To rebuild
the report:

```sh
dart run benchmark/value_store/summarize.dart build/value_store_profiles/<run>
```

For call-site optimizations, `--library-source /path/to/saved/package` supplies
the entire starting `lib/` before each variant is applied; tests and workloads
come from the current checkout. `combined` means that supplied library unchanged.
Freeze the library before editing it so the comparison does not accidentally
include the candidate on both sides. Every variant is prepared and parsed before
any native builds begin.

```sh
dart run benchmark/value_store/run.dart \
  --library-source /path/to/saved/package \
  --variants combined,scoped_guard \
  --suites dependency,dependency_shapes,sparse_writes \
  --modes jit,aot --passes 3 --trials 9
```

`scoped_guard` reuses collection maps during synchronous propagation and the last
reverse dependency set during deletion. An outer guard keeps traversal setup
off empty dependency lookups. All local references are released when the operation
returns. `batch_clean` and `scoped_clean` are intermediate controls isolating
propagation alone and both changes before that outer guard.
`touch`, `delete_recent` and `batch_buckets` are earlier experimental controls.
These transforms are relative to the supplied library; use a saved starting
version to reproduce a before/after comparison once an optimization is adopted.

The report keeps runtime modes separate. It includes pooled medians and the range
of per-process medians, alongside raw samples. That range is not a confidence
interval. `manifest.json` records Flutter/Dart versions, hardware/OS, source and
binary hashes, dependency versions and run settings; `receipts.json` records
commands and exit codes. `first_sample_us`, where available, is the first timed
sample of that workload, not app-startup latency. RSS fields include the Flutter
engine and native libraries and are not allocation or retained Dart heap metrics.

## Workloads

- `lookup`: exact shallow/deep reads, missing paths, empty-store operations,
  collection access and subtree deletion, with a flat-map comparison.
- `store_core`: prebuilt shallow/deep paths for reads, value/node/missing-path
  existence checks, collection lookups, ancestor queries, new writes, overwrites,
  deletion, and ordered set/map extraction across flat, bucketed, singleton,
  deeply nested, and duplicate-value shapes. Reports milliseconds per named batch;
  operation counts are included with each row. Shared by standalone and Flutter runs.
  Path controls include UUID-like IDs, long segments, Unicode and underscore runs;
  mutation controls include separate branch creation and shared-value reference counts.
- `dependency_shapes`: poor collection locality, shared summaries and cycles,
  and alternating source dependencies during deletion. Checks reached document
  events and reverse-index cleanup outside timing.
- `sparse_writes`: 1k updates in large resident collections, with zero or one
  dependent per source. Includes writes and broadcast flush; verifies event
  counts and final data outside timing.
- `traversal`: subtree aggregation, list export, direct collection access,
  sparse known-ID reads, duplicate visits and distinct-value collection.
- `traversal_apis`: callback and typed-callback controls, recursive generators,
  a hand-written iterator, direct bucket iteration, specialized walkers and eager
  extraction. Compares aggregation, list export, flat/nested dependency cleanup
  and overlapping-set union. Includes concrete list/map loop-style controls.
  Loop accumulators have separate lexical scopes from callback accumulators;
  result validation is outside timing. Export measures list construction only,
  unlike the older `iterable` suite's export-plus-sum workload.
- `iterable`: callback versus lazy iteration, export, a dependency-cleanup
  model and merging overlapping dependent sets.
- `extraction`: direct extraction versus lazy `toSet`, plus shared bucket
  traversal. Covers unique integers, retained entry objects and repeated values.
- `extraction_cost`: separates tree navigation from set construction; compares
  ordered extraction candidates, an unordered `HashSet` diagnostic, and prebuilt
  list/set controls. Includes object equality, duplicates and trees with many
  small/deep nodes. The cached-set control omits index maintenance and memory
  costs; it is not an implemented cache. Duplicate-value sums have different
  semantics: traversal counts occurrences, extraction sums distinct values.
- `dependency`: actual Loon registration, source updates, delivery, coalesced
  writes and deletion. Shapes are 100k shared dependents, four queries over 10k
  dependents, 100k documents across 100 source groups, and 20k nested documents. Timers are drained
  deterministically with `fake_async`; the stopwatch measures real execution.
  This measures CPU work, not device event-loop latency or frame smoothness.
- `documents`: retained construction results for 100k flat/nested handles,
  100k `fromPath` calls, first document hashes, snapshot hashing, and 1k document
  updates that change one of 32 dependencies. Validates full identities and
  forward/reverse memberships outside timed intervals.

`run_retention.dart` uses separately built profile hosts. Each fresh process
requests VM service GC and collects live class counts/shallow bytes plus isolate
heap usage at baseline, registration, handle replacement, subtree deletion and
clear. It covers one shared source and empty dependency sets, with three fresh
processes per variant and reversed order on alternate passes. GC requests are not
guarantees; the recorded service-GC timestamp and post-delete counts help assess
whether collection occurred. Heap profiles are neither release timings nor
dominator retained-size measurements. The collector runs inside the target
isolate, so whole-heap totals include some measurement machinery; class counts
are the more specific representation evidence.

The test wrappers invoke the same functions; semantics checks stay in tests.
`collection_lookup_demo_test.dart` remains a runnable proposal for scoped
collection lookup reuse, including transitive dependencies, coalescing and a cycle.

Quick correctness/debug runs:

```sh
PROFILE_WARMUPS=1 PROFILE_WARMUP_MS=0 PROFILE_TRIALS=1 flutter test benchmark/value_store/iterable_profile_test.dart --concurrency=1
PROFILE_WARMUPS=1 PROFILE_WARMUP_MS=0 PROFILE_TRIALS=1 flutter test benchmark/value_store/extraction_profile_test.dart --concurrency=1
```

These headless test timings are diagnostic only. Workloads, runner, source
variants, report generation and log decoding are all Dart. The previous Python
tools have been removed; historical reports retain their original receipts.

## CPU/memory diagnosis and target-device qualification

Native macOS AOT is a useful early gate, not proof of iOS/Android behavior. Before
accepting a production optimization, run representative workloads on the target
physical device in profile/release mode. Keep hardware, SDK, workload size and
comparison order consistent. Separate steady-state work from startup/first use.
For retention changes, inspect Dart heap retention and allocations explicitly;
process RSS alone cannot settle the trade-off. Use release for final timing and
profile for CPU/heap diagnosis; do not pool their samples.

The generated host can be used with `flutter run --profile` and DevTools. From
`<run>/hosts/combined`, point `--target` at that run's copied
`packages/combined/benchmark/value_store/native_main.dart`:

```sh
flutter run -d macos --profile --target <absolute-native-main.dart> \
  --dart-define=PROFILE_SUITE=dependency \
  --dart-define=PROFILE_EXPECT_MODE=profile \
  --dart-define=PROFILE_VARIANT=combined \
  --dart-define=PROFILE_START_DELAY_MS=15000 \
  --dart-define=PROFILE_EXIT=false
```

The startup delay gives time to attach DevTools. Each operation's setup and
validation still run but are outside its timed interval. Profile traces may alter
execution timing and should be retained as diagnostic runs.

For physical iOS/Android qualification, add the platform to the **generated host**
(`flutter create --no-pub --platforms ios,android .`), resolve its pinned packages,
configure the normal device signing if required, and use the same entrypoint and
Dart defines with `-d <physical-device-id>`. Use `--release` and
`PROFILE_EXPECT_MODE=aot` for final timing. Repeat both variants with reversed
order and capture each run's console log. This device path is documented, not
claimed as tested until an actual device receipt exists.

The entrypoint also emits bounded-size framed JSON to the device log:

```sh
dart run benchmark/value_store/decode_log.dart device.log --mode aot --out device.json
```

The decoder requires exactly one complete successful result and verifies the
reported mode. Keep a separate device record of hardware, SDK, build mode and
source revision with the resulting JSON.

References: [Flutter performance guidance](https://docs.flutter.dev/perf/ui-performance),
[Flutter build modes](https://docs.flutter.dev/testing/build-modes), and the Dart
project's [multi-runtime benchmark harness](https://pub.dev/packages/benchmark_harness#bench-command).

## Variants and experimental API contracts

| Variant | Store fast paths | Cached document identity | Additional experiment |
| --- | --- | --- | --- |
| baseline | No | No | Retained dependency entries + extractValues |
| store | Yes | No | — |
| identity | No | Yes | — |
| combined | Yes | Yes | Current working library |
| touch | Yes | Yes | Dedicated dependent-touch path |
| visitor | Yes | Yes | Direct dependency-entry traversal |

`variants.dart` applies fail-closed transforms only to copied packages. Update its
anchors when production methods change. The default comparison does not include
all historical prototypes; select them explicitly when investigating them.
Each baseline disables the features listed above in the current source; it is
not a frozen historical checkout. The store fast paths are the incremental path
parsing in `get` and the shared `_lookup` walk, plus the empty-store delete guards.
Writes, deletes and the recursive walks keep incremental parsing in every variant.
Archived runs describe their measured source
using hashes, SDK versions and command receipts.

The document comparison keeps the earlier store optimizations, dependency-set
snapshot fix and document path/hash caching in every variant:

| Variant | Four small allocation changes | Forward dependency representation |
| --- | --- | --- |
| document_before | No | Retained `_DependencyEntry` |
| document_before_paths | No | Sets; extract path map and reconstruct documents |
| combined | Yes | Retained `_DependencyEntry` |
| document_paths | Yes | Sets; extract path map and reconstruct documents |

The four changes are fixed-arity `Object.hash`, cached collection paths,
membership loops instead of temporary difference sets, and reference-path
parsing without splitting/rejoining intermediate collections. Both Document and
Collection factories share the parser. No callback traversal API is used in this
comparison, so it evaluates the entry model as currently implemented.

The two path-reconstruction controls store raw sets instead of entries. Their
validation excludes only the entry-specific JSON serialization test; dependency
behavior, subtree cleanup and all other core checks still run. Production
`inspect()` returns the stored entries, whose `toJson()` encodes document paths.
Archived measurements retain the inspection format of their recorded revision.

The traversal helpers are proposals using `inspect()` to access the current tree.
They visit the target's own value plus all descendants, including nulls and
repeated values. They must not structurally mutate the traversed store during
iteration. A fresh iteration reads the current store; it is not a snapshot.
Consume values before deleting their source subtree. Mutating a separate reverse
index during forward traversal is safe.

`visitor_draft.dart` uses a callback; `iterable_draft.dart` delegates existing
bucket iterators with `yield*`; `value_batches_draft.dart` explores one private
bucket traversal shared by lazy iteration and eager extraction. These target
ValueStore only. ValueRefStore's precomputed distinct-value index remains a
separate extraction fast path. No production traversal API has been added.

`traversal_api_draft.dart` adds an explicit-stack iterator plus concrete sum,
export, cleanup and union walkers as performance controls. The manual iterator
preserves nulls, duplicates, depth-first order, fresh iteration and early stopping;
its traversal stack grows with tree depth. Specialized walkers duplicate traversal
code and couple it to the operation, so a timing win alone does not justify their
adoption as public APIs. Direct bucket consumers reuse `value_batches_draft.dart`.

Use `getChildValues()` for direct collection children and exact `get()` for sparse
known paths. Key/entry traversal would also need to build full paths; the
value-only path intentionally avoids that work.

Historical JIT-only investigations:
[initial assessment](results/2026-09-15.md),
[lazy iterable comparison](results/2026-09-15-iterable.md), and
[extraction API comparison](results/2026-09-15-extraction.md).
These remain evidence for their recorded execution modes, not AOT receipts.
