# Core store optimization — September 20, 2026

[All source snapshots, raw samples, build hashes and receipts](2026-09-20-store-core.json)

This records the first optimization pass. The subsequent
[delimiter-scanning follow-up](2026-09-20-path-scanning.md) adds further improvements.

## Implementation

- Preserve the incoming incremental parsing for reads, writes, deletion, grafting and reference-store operations.
- Resolve `hasPath` in one walk. The incoming implementation called `get` and then walked again for non-value paths and misses.
- Return the owning node and final segment together for subtree extraction, avoiding a second full path scan.
- Visit map keys and child nodes together with `Map.forEach`, and stop at leaf value buckets. Map extraction also avoids iterating through `MapEntry` wrappers.
- Keep the dedicated exact-read loop for `get`, instead of routing it through a helper that also returns node/segment records and existence flags.
- Collect ancestor values in one iterative walk. Keep nearest-ancestor search recursive: it can return a deep match without reading every ancestor value.
- Keep ordered, fresh mutable extraction results, nullable values, delimiter semantics, inspection shape and the existing public API. No retained cache or additional index is introduced.

## Flutter release AOT: incoming workspace versus selected implementation

Milliseconds per batch. 2 fresh processes per variant, 11 measured samples per operation in each process, five warmups and at least 200 ms of warmup phase time. The rest of Loon is held constant.

| Operation | Incoming | Optimized | Time reduction |
| --- | ---: | ---: | ---: |
| 100k shallow exact reads | 13.690 | 13.278 | 3.0% |
| 100k deep exact reads | 39.395 | 39.184 | 0.5% |
| 100k deep node-existence checks | 53.083 | 27.187 | 48.8% |
| 100k deep late misses | 65.076 | 33.483 | 48.5% |
| 20k single-value extractions at deep paths | 11.601 | 8.304 | 28.4% |
| Extract values across 20k singleton nodes | 3.041 | 1.972 | 35.2% |
| Extract values across 20k deep branches | 10.507 | 6.169 | 41.3% |
| Flatten a map across 20k deep branches | 24.581 | 19.727 | 19.7% |
| 20k ancestor-map extractions | 50.748 | 44.323 | 12.7% |

## Exact historical store comparison

`main` is `82b8a7b`; `pr` is committed PR head `d18a5e4`; `incoming` preserves the uncommitted store refactor present when this task started. These are exact source snapshots, not feature-disabled approximations. The JSON archive includes their complete source text.

This table is a separate standalone Dart AOT series. Each variant has 2 fresh processes and 9 samples per operation per process. It isolates store algorithms from Flutter; do not compare its absolute times to the Flutter table.

| Operation | main | Committed PR | Incoming | Optimized |
| --- | ---: | ---: | ---: | ---: |
| 20k deep exact reads | 9.931 | 6.710 | 6.598 | 6.533 |
| 20k deep new writes | 11.718 | 12.434 | 8.678 | 8.130 |
| 20k deep overwrites | 11.438 | 11.239 | 7.595 | 7.138 |
| 20k deep leaf deletions | 11.476 | 11.178 | 8.354 | 7.614 |
| 100k deep node-existence checks | 35.916 | 35.868 | 53.687 | 26.954 |
| 20k ancestor-map extractions | 114.808 | 114.822 | 53.792 | 44.248 |
| Extract values across 20k deep branches | 10.415 | 10.765 | 11.052 | 6.277 |

The incoming parsing changes already account for much of the improvement against main in writes, deletes and nearest-ancestor lookups. This pass chiefly removes the double-walk regression and reduces extraction costs.

## Whole dependency workloads

| Operation | Incoming | Optimized | Time reduction |
| --- | ---: | ---: | ---: |
| Notify 100k shared dependents | 68.766 | 69.689 | -1.3% |
| Delete 100k shared dependents | 24.416 | 25.590 | -4.8% |
| Notify 10k dependents across four queries | 23.206 | 23.316 | -0.5% |
| Register 20k nested dependents | 40.540 | 39.877 | 1.6% |
| Notify 20k nested dependents | 18.765 | 19.957 | -6.4% |
| Delete 20k nested dependents | 4.553 | 4.604 | -1.1% |

The microbenchmark gains do not imply a matching speedup for complete notifications. Graph updates, document handling, filtering and stream delivery remain. The final series includes about 5% slower shared-dependent deletion and 6% slower nested notification; earlier repeats varied in direction. Overall engine throughput is mixed, not an established improvement. Per-process medians and all samples remain in the raw archive.

## Experiments and remaining cost

An iterative nearest-ancestor prototype was rejected: the first AOT screen increased a 20k deep nearest-leaf batch from 11.608 to 17.204 ms. It inspected every ancestor even when the deepest value matched. Iteration remains useful for extracting all ancestors, where every value is needed.

The extraction-cost controls show that flat buckets are dominated by constructing the distinct result set. Faster tree traversal helps singleton/deep-node shapes much more. The unordered-set and lazy traversal alternatives retain their separate semantics and are not production changes.

The original focused lookup repeat tested the earlier shared-getter candidate using the same Flutter binaries, 10 warmups, at least 500 ms warmup, 21 trials, three processes and reversed order. It and the extraction-cost diagnostics are archived separately, not pooled into the final dedicated-getter series. Exact reads in the final series are comparable to the incoming implementation; small percentage changes are not evidence of a reliable read-side improvement.

## Representation trade-off

The final Flutter lookup control performs 100k deep reads in 39.184 ms through the tree versus 1.806 ms through a flat map of prebuilt full paths. Conversely, selecting and summing a 1k-value collection costs 0.013 ms with the tree versus 1.188 ms when scanning 100k flat entries. The trie still earns its place for collection and subtree access. A second flat index could accelerate exact reads, but adds retained keys/references and consistency work for writes, deletions and grafts; mutable maps exposed through inspection also permit changes that bypass normal mutation hooks. No such cache is introduced here.

## Validation and limits

- Expanded store checks cover nullable values, odd delimiter runs, node existence, ancestor/root fallback, extraction order, independent snapshots and 2,500 randomized write/delete steps with subtree and ancestor oracles.
- Both Flutter variants passed 150 core/benchmark checks before native timing. Final validation passed all 242 core/native/benchmark tests and 42 Chrome web tests (284 total); `flutter analyze --no-pub` reported no issues.
- The updated default baseline transform also compiled and passed 133 core/store-workload tests. Recorded final source hashes matched the working library at the end of this pass.
- Dart 3.12.2; Flutter 3.44.4; macOS arm64. These are desktop CPU measurements, not mobile latency or frame-time guarantees.
- JIT and AOT remain separate in the archive. There were host-load bursts; ranges of per-process medians are evidence of variability, not confidence intervals. Small differences should not be treated as proven improvements.
- Setup, fixture reset and checks are outside timing. Warmup time includes fixture preparation/checks. Set validation remains active in release builds.
- This pass adds no retained index/cache; it does not claim measured allocation-byte or retained-heap savings.

See [the profiling workflow](../README.md) for reproduction commands. The standalone runner preserves source text so the incoming uncommitted baseline remains recoverable.
