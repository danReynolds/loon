# Parsed-path retention and cache experiments — September 20, 2026

[Source snapshots, raw samples, receipts and heap captures](2026-09-20-path-cache.json)

Production remains the scanner from the [previous pass](2026-09-20-path-scanning.md). This experiment adds no production cache or Document field. All variants run in disposable copies.

## Ownership and cleanup

- Owner metadata is created lazily and collected with its last owning handle. Deleting a document does not free metadata on a handle still held by application/dependency code. This has no fixed global bound.
- The bounded shared prototype allows 512 KiB of estimated metadata, at most 1,024 entries, and paths of at most 512 UTF-16 code units. A second prototype uses 2 MiB/4,096 entries. Eviction happens synchronously on admission; a linked list makes eviction constant-time.
- Those are engineering accounting budgets, not exact Dart-heap limits. Entry and key limits remain necessary. The measured charged bytes are not a per-entry upper bound on physical VM bytes.
- Both shared prototypes retain only immutable strings and parsed segments. Every read still walks the current store, so deletion/grafting needs no cache invalidation and cannot keep deleted document values alive. Engine reset clears the shared cache. Ordinary GC reclaims unreachable allocations later; production does not force GC.
- The one-entry alternative admits a parsed plan only on the second consecutive read. Changing paths releases the previous plan. At its 512-code-unit limit, its maximum accounting charge is about 14.2 KiB for delimiter-heavy paths; an ordinary fixture path is charged 688 bytes. It is not universally a sub-kilobyte cache.

## Retained memory

Eight separate Dart JIT workers, one per shape/strategy, use 100,000 synthetic handles. An external collector requests GC and captures live heap/class counts after seeding, parsing, deleting all stored values, releasing all handles, and clearing the cache. Diagnostic execution is separate from release timings.

| Strategy | Shallow paths | Deep paths | Release point |
| --- | ---: | ---: | --- |
| Parsed metadata on 100k handles | about 14.4 MB added | about 28.8 MB added | Last owning handle released |
| 512 KiB-budget LRU | about 0.295 MB retained; 1,024 entries | about 0.366 MB retained; 762 entries | Eviction or cache clear |
| 2 MiB-budget LRU | about 1.180 MB retained; 4,096 entries | about 1.465 MB retained; 3,048 entries | Eviction or cache clear |
| Recent-path cache | One key/plan | One key/plan | Next distinct path or clear |

Owner numbers use parsed-minus-seeded live-heap deltas and exclude the cost of adding a nullable field to every real Document (the fixture already has that slot). LRU numbers use owners-released minus cache-cleared live-heap deltas. These are approximate decimal MB, not RSS, dominator sizes, AOT/mobile layout promises, or worst-case bounds. Small recent-cache heap deltas are too close to measurement overhead for a reliable exact-byte claim.

All 100,000 owned plans survived deletion while their handles remained, then disappeared when those handles were released. Shared plans survived handle release but all disappeared on cache clear. Cleared map/list container objects may remain; VM heap capacity need not shrink immediately.

## Standalone Dart AOT

Milliseconds per 100,000 deep-path reads. Two fresh processes, seven measured trials per operation, three warmups and at least 100 ms of warmup phase time. Method order reverses between passes. Warm rows retain plans across trials; cold rows in the archive include admission/parsing. JIT is archived separately.

| Access pattern | Scanner | Owned plans | LRU 512 KiB | LRU 2 MiB | Recent path |
| --- | ---: | ---: | ---: | ---: | ---: |
| Cycle 128 paths | 21.459 | 12.675 | 16.691 | 16.784 | 22.627 |
| Cycle 2,048 paths | 22.516 | 13.708 | 46.038 | 16.892 | 23.000 |
| Scan 100k distinct paths | 27.418 | 16.982 | 53.390 | 54.095 | 27.936 |
| Five consecutive reads per document | 23.655 | 13.900 | 24.581 | 24.849 | 21.510 |
| 90% hot reads, 10% new paths | 22.448 | 13.496 | 20.817 | 21.152 | 23.517 |

Owned plans win when reused but their cold sequential pass takes about 61.5 ms versus 27.5 ms for scanning. The 512 KiB LRU improves the small hot set by about 22%, yet roughly doubles sequential time and thrashes on the 2,048-path set. Increasing capacity fixes that working set but still loses on scan churn. Recent-path admission avoids most scan cost but provides only a roughly 9% warm win on consecutive reuse.

An earlier draft used Map.keys.first for oldest-entry eviction. Repeated deletion/insertion made this costly; sequential AOT times were roughly 100 ms at 512 KiB and 232 ms at 2 MiB. Linked eviction removes that avoidable cost, but the remaining miss/admission overhead still loses. The rejected implementation and measurements are preserved separately.

## Full Flutter release AOT

Two fresh processes per variant, nine trials per operation, five warmups and at least 150 ms of warmup phase time. Same full library and workload; only exact get gains a shared cache, with engine-reset cleanup. Writes/deletes remain the scanner. Source updates include dependency propagation and broadcast flush; persistence is disabled. Times are milliseconds per batch and must not be pooled with the standalone series.

| Operation | Current scanner | LRU 512 KiB | Recent path |
| --- | ---: | ---: | ---: |
| 100k shallow exact reads | 9.347 | 28.712 | 11.362 |
| 100k deep exact reads | 25.764 | 53.724 | 28.405 |
| Register 100k shared dependents | 166.546 | 218.934 | 204.309 |
| Notify 100k shared dependents | 52.058 | 77.580 | 65.081 |
| Delete 100k shared dependents | 22.056 | 25.311 | 19.840 |
| Notify 10k dependents across four queries | 22.366 | 33.923 | 23.959 |
| Notify 1k of 100k grouped dependents | 0.490 | 0.661 | 0.568 |
| Notify 20k nested dependents | 13.948 | 18.225 | 16.763 |
| Delete 20k nested dependents | 3.996 | 4.592 | 3.876 |

## Validation and decision

Four new tests cover split semantics (empty/Unicode/underscore boundaries), immutable plans, fresh reads after deletion/recreation/clear/graft, byte/entry/key admission, LRU eviction and recent-path replacement. All 156 core and benchmark tests pass in each of the three complete-library variants. Analyzer passes. Release-active checks verify results outside timing.

Keep the production scanner and leave these caches experimental. In full dependency propagation, the shared 100k case takes about 52 ms with the scanner, 78 ms with LRU and 65 ms with the recent cache. The nested case takes about 14/18/17 ms respectively. The recent cache helps some deletion cases, but neither shared design provides a broad improvement. Per-handle plans deliver stronger repeated-read wins only after paying setup and retention costs; this experiment does not establish an engine-level win for adding them to Document.

If a future targeted cache proves useful, start with a shared 512 KiB accounting budget per engine/isolate, entry/key limits, eviction on admission and clear on engine reset. A promising next investigation is reuse within one operation or sharing parent-path metadata across a collection, so the work and retention track active use instead of the total document count. Neither approach is implemented or claimed faster here.

Measurements are macOS arm64 with Flutter 3.44.4 / Dart 3.12.2. Process medians, host load and raw samples are archived; small changes are not treated as reliable wins. No mobile-device or web performance conclusion is implied.
