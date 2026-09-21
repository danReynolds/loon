# Scoped dependency traversal — September 20, 2026

[Raw JIT/AOT samples, exact source snapshots and receipts](2026-09-20-scoped-traversal.json)

This compares the scanner-based working library at the start of this pass with operation-local reuse of existing ValueStore maps. It follows the [shared-path-cache experiment](2026-09-20-path-cache.md); it does not compare against main or change the store representation.

## Decision and complexity

Keep scoped propagation and the small shared-dependency deletion reuse, with the empty-graph guard. The release gains are large enough to justify the added branches: shared and nested propagation take about 71% and 81% less time, respectively. This is an engine call-site improvement using the existing tree, not another storage representation or persistent cache.

- Propagation: resolve event and reverse-index collection maps and address sibling documents by ID. Retain only the last map from each store, not a map of all collections. Switching collections resolves again. Empty graphs return early; unusual parent/ID boundaries use ordinary path reads/writes.
- Deletion: reuse the last dependency set during one cleanup operation. The existing removal helper remains responsible for pruning and returns the remaining set, or null after removal. No duplicated pruning algorithm is needed in the selected draft.
- The propagation change is about 50 net lines, including a private helper that keeps closure setup off empty dependency lookups; deletion is about 10. There is no new public API, persistent field, parsed-path cache, second index, timer or invalidation protocol. The ValueStore implementation itself is unchanged in this pass.
- The maps are valid only during synchronous propagation, which reads the reverse index and adds events while invalidating a separate observer-value store. No user callback is invoked by this walk. Deletion similarly retains its set only until the cleanup call returns. These references do not survive into a later operation; there is no added persistent memory budget.

## Candidate screen

Four variants: current scanner, a dedicated touch helper removing the duplicate event lookup, one recent reverse set during deletion, and scoped collection-map propagation. Each passed 159 core/benchmark tests. Two fresh processes per JIT/AOT variant, seven measured trials, five warmups and at least 150 ms of warmup phase time.

The propagation prototype showed large gains across dense, sparse-group, scattered-collection and shared-cycle cases. The touch-only control improved less. The deletion prototype helped shared dependency sets but not grouped deletion with little consecutive reuse. Some unchanged controls also moved materially, so small percentages are not treated as wins.

The first bucket draft had a syntax error caught before timing. Its corrected build was validated separately; the other three validated binaries were reused. The replay checked identical workload source and executable/Dart-artifact hashes before running the complete matrix. Both successful and failed build receipts remain in the archive.

The initial bucket draft also showed slower nested deletion. The confirmation below tests a simplified walk (one local visitor, one boundary check per document, early return for empty graphs), both independently and with cleaned-up deletion reuse. Do not infer final behavior from the initial prototype.

The first three-process confirmation still showed an empty-graph regression: about 0.82 ms to 0.96 ms per 1,000 ordinary writes. The final candidate moves traversal and its closure context into a private helper invoked only for nonempty dependency sets. It was validated/built separately, then compared with the same baseline binaries in a new full matrix. The archived pre-guard series isolates the earlier two changes.

## Confirmation in Flutter release AOT

Three fresh processes per variant, eleven samples per operation, five warmups and at least 200 ms of warmup phase time. Process order alternates. Milliseconds per named batch; positive percentages mean less time. Persistence is disabled. Before is the exact saved starting library, and selected production source hashes are verified against the measured candidate.

| Operation | Before | Selected | Less time |
| --- | ---: | ---: | ---: |
| Notify 100k shared dependents | 59.928 | 17.372 | 71.0% |
| Notify 20k nested dependents | 16.253 | 3.156 | 80.6% |
| Notify 1k of 100k grouped dependents | 0.525 | 0.217 | 58.7% |
| Notify 10k dependents and four queries | 22.078 | 18.378 | 16.8% |
| Delete 100k shared dependents | 25.411 | 16.380 | 35.5% |
| Delete 20k nested dependents | 4.381 | 3.502 | 20.1% |
| Delete 100k grouped dependents | 32.927 | 32.260 | 2.0% |
| Delete alternating source dependencies | 4.777 | 4.813 | -0.8% |
| Propagate across 5k scattered collections | 15.030 | 7.194 | 52.1% |
| Propagate through a shared summary and cycle | 19.715 | 11.618 | 41.1% |
| 1k writes among 50k docs, no dependents | 0.948 | 0.881 | 7.1% |
| 1k writes among 100k docs, one dependent each | 2.476 | 2.206 | 10.9% |

The guard removed the observed ordinary-write regression in this repeat: 1,000 writes without dependents took 0.95 ms before and 0.88 ms after in AOT; JIT was essentially flat at 1.04 versus 1.03 ms. Treat this as a no-regression check, not a claim that propagation optimization makes independent writes faster.

### Trade-offs

Shared-set deletion improves by about 36% in AOT and 27% in JIT. The added last-set comparison only helps when consecutive entries share a dependency: grouped and alternating deletion are essentially flat in the final AOT series, but respectively about 8% and 15% slower in JIT. The earlier AOT confirmation also had roughly 9% and 15% regressions on those cases. This is a deliberate trade-off for about ten added lines, not a universal deletion speedup.

AOT query totals improve less than propagation alone (about 17%), because query delivery remains the dominant cost. Registration is not optimized here: the 10k-query seed is about 9% slower in the final AOT series, while other seed cases vary in both directions; shared/nested registration also rises in the JIT series. Those broader movements are visible in the raw data and are not attributed to a specific allocation or GC mechanism without profiling it.

## Isolate the two changes before the empty-graph guard

Separate three-process series, nine samples per operation. These values describe the intermediate versions, not the final guarded candidate.

| Operation | Before | Propagation only | Both |
| --- | ---: | ---: | ---: |
| Notify 100k shared dependents | 57.496 | 16.730 | 17.490 |
| Delete 100k shared dependents | 23.240 | 24.978 | 15.720 |
| Delete 20k nested dependents | 4.329 | 6.299 | 3.515 |
| Delete 100k grouped dependents | 29.282 | 28.965 | 31.824 |
| Delete alternating source dependencies | 5.058 | 8.815 | 5.827 |
| Sparse writes without dependents | 0.817 | 0.880 | 0.957 |

## Evidence and limits

- Added explicit propagation tests for unusual segment boundaries, diamonds, cycles, event-store clear/reuse, shared-dependency deletion, survivors and recreation. Existing observer/query semantics and serialization tests also pass.
- New workload checks verify affected documents and event types outside timing, including that cycles preserve a pending modified event. Sparse-write checks verify the number of source/dependent events, final data and drained broadcasts. Checks remain enabled in release.
- The scattered case has 20k documents across 5k collections. Shared-cycle propagation has 20k leaves converging on one summary that points back to the source. Alternating-dependency deletion intentionally defeats the one-entry reuse. Sparse writes update 1k distinct documents among 50k sources, with either no dependents or another 50k one-to-one dependents.
- Standard dependency totals include source write plus broadcast flush. Graph-shape propagation measures the synchronous queueing operation. Sparse writes include mutation and flush, with intermediate correctness checks excluded from the accumulated stopwatch.
- JIT is archived separately from AOT. Host-load bursts and per-process variation are recorded. Process-median ranges are not confidence intervals; small gains or regressions on unchanged controls are inconclusive.
- Final validation: 252 core/native/benchmark tests and 44 Chrome tests, with no analyzer issues. All library source hashes match the selected measured variant.
- Flutter 3.44.4 / Dart 3.12.2, macOS arm64. This is desktop performance evidence, not a physical mobile-device measurement.

## Where to stop

The broad shared-cache and parser experiments were reaching diminishing returns for their complexity. This pass finds a larger opportunity in how the engine uses the tree: avoid repeated traversal when a synchronous operation already knows it is visiting siblings or one shared dependency. Further fields, global caches or indexes should clear a much higher bar than a noisy 5% microbenchmark improvement.
