# Store path-scanning follow-up — September 20, 2026

[Source snapshots, raw samples and receipts](2026-09-20-path-scanning.json)

This follows the [core store pass](2026-09-20-store-core.md). `before` is the working tree at the end of that pass, including its extraction and path-walk improvements. `main` is commit `82b8a7baca5faa8885e9a5c5d3effba701315896`.

## What changed from main, and why

| Area | main | Current implementation and reason |
| --- | --- | --- |
| Path traversal | Split every path into a list before walking it | Parse only visited segments; remove the list and stop parsing on the first missing node |
| Exact reads and empty stores | Split and call the general node walker | Dedicated read loop and an empty-store return keep the hot operation small |
| Node and subtree resolution | Split, remove the final segment, walk the parent | Shared lookup resolves the node, existence, or parent/final-segment record in one walk |
| Ancestor queries | Recursion plus sublist/join to build returned paths | Use substrings of the original path; collect all ancestors iteratively while nearest-match search keeps its useful deepest-first recursion |
| Subtree extraction | Iterate child keys then look each child up; create entry wrappers when flattening values | Map.forEach supplies keys and values together; leaf buckets return immediately; ordered distinct-set snapshots remain intact |
| Writes, deletes and grafting | Pass a split segment list through the operation | Advance a cursor into the original string, keeping the existing mutation/pruning behavior; empty deletes return early |
| Reference store | Split paths and copy a redundant sublist in getRefs | Share the incremental node walker and preserve the existing reference counts |
| Delimiter search, added in this follow-up | General string splitting; the earlier optimization used indexOf | A small scanner specializes the fixed two-underscore delimiter, including the shared reference-path utility |

`hasPath` already used one parent traversal on main. The double traversal removed in the earlier pass was introduced by the intermediate shared-lookup refactor, not by main.

## Experiments

Four isolated candidates were screened in Dart JIT and AOT: explicit Map typing/cached bucket access, a code-unit delimiter scanner, a single-character indexOf scanner, and putIfAbsent plus reduced map work during mutation. The custom scanner provided the strongest broad signal. The bucket/mutation changes were mixed, and were not added to production.

The two scanner candidates were repeated in reversed process order with UUID-like IDs, 128-character segments, Unicode and underscore runs. Both improved on the original multi-character indexOf in these shapes; direct code-unit scanning performed better on the short deep-path cases. The single-character indexOf approach remained competitive for long segments. The selected helper is small and reused by the base store, mutation operations, reference store and reference-path splitting.

No node cache, flat index, new public traversal API or changed serialization representation was added.

## Final Flutter release AOT

Milliseconds per batch; positive percentages mean less time. Three fresh processes per variant, eleven measured trials per operation in each process, five warmups and at least 200 ms of warmup phase time. Only the store/path utility files differ between variants.

| Operation | Before this follow-up | Scanner | Time reduction |
| --- | ---: | ---: | ---: |
| 100k shallow exact reads | 13.594 | 11.081 | 18.5% |
| 100k deep exact reads | 38.755 | 27.060 | 30.2% |
| 20k deep new writes | 7.709 | 5.732 | 25.6% |
| 20k deep overwrites | 6.767 | 4.774 | 29.5% |
| 20k deep leaf deletions | 7.501 | 6.214 | 17.2% |
| 100k deep node-existence checks | 26.532 | 17.330 | 34.7% |
| 10k reads with UUID-like IDs | 4.442 | 2.973 | 33.1% |
| 10k reads with long segments | 19.224 | 13.335 | 30.6% |
| 10k Unicode-path reads | 6.001 | 5.070 | 15.5% |
| 20k writes creating separate branches | 10.812 | 10.728 | 0.8% |
| 20k shared-value reference-store writes | 16.164 | 13.784 | 14.7% |

## Full dependency workloads

Source-update times include dependency propagation and the broadcast flush. Shared/nested cases have no query observers; the four-query case includes query delivery. Persistence is disabled in these CPU workloads.

| Operation | Before this follow-up | Scanner | Time reduction |
| --- | ---: | ---: | ---: |
| Notify 100k shared dependents | 69.803 | 54.192 | 22.4% |
| Delete 100k shared dependents | 25.126 | 22.674 | 9.8% |
| Notify 10k dependents across four queries | 23.446 | 20.974 | 10.5% |
| Notify 20k nested dependents | 19.390 | 14.306 | 26.2% |
| Delete 20k nested dependents | 4.584 | 4.151 | 9.4% |

## Separate exact-source Dart AOT comparison

Two fresh processes and nine measured trials per operation. These absolute times must not be pooled with Flutter timings. All final sources and both JIT/AOT results are preserved in the JSON archive.

| Operation | main | Before this follow-up | Scanner |
| --- | ---: | ---: | ---: |
| 20k deep exact reads | 9.954 | 6.546 | 4.489 |
| 20k deep new writes | 12.367 | 8.184 | 5.891 |
| 20k deep leaf deletions | 10.970 | 7.883 | 5.580 |
| 100k deep node-existence checks | 36.647 | 26.953 | 17.086 |
| 20k ancestor-map extractions | 113.969 | 44.249 | 40.248 |
| Extract values across 20k deep branches | 9.912 | 5.774 | 5.557 |

## Correctness and limits

- Added split-based randomized oracles for both ValueStore and ValueRefStore, covering Unicode, empty segments, odd underscore runs, writes, deletes, pruning and reference counts. They pass against both the old parser and the selected scanner.
- The suite now also measures UUID-like IDs, long segments, Unicode, underscore runs, new branches and reference-store mutations. Fixture preparation and correctness checks stay outside timing; checks remain active in release builds.
- Final validation: 244 core/native/benchmark tests plus 42 Chrome tests (286 total), with no analyzer issues. Final recorded library hashes match the working tree.
- Flutter 3.44.4 / Dart 3.12.2 on macOS arm64. Chrome tests establish correctness; timing results establish native desktop behavior, not browser or physical-device performance.
- Host-load bursts are present in the archive. Per-process ranges expose variability; they are not confidence intervals. Do not interpret small differences or unchanged traversal controls as guaranteed gains.

The tree continues to make collection/subtree access efficient. A promising direction for larger exact-read gains is avoiding repeated segment materialization and hashing, for example with reusable parsed paths or a second index. Those alternatives introduce retained-memory or consistency/API trade-offs and were not adopted here.
