# Scoped traversal cleanup and headless profiling — September 21, 2026

[Raw samples, source snapshots, receipts and focus audits](2026-09-21-scoped-cleanup.json)

## Decision

Keep the starting optimized engine implementation. Adopt the headless profiling harness, but leave the cleanup helpers in the profiling drafts only. The cleaner `_CollectionValues<T>` proposal centralizes parent/map bookkeeping for the event and reverse-index stores, but the final comparison did not justify adopting it.

The helper is 28 lines including the document-boundary predicate. The propagation method loses about twenty lines of repeated bookkeeping. This improves separation of responsibilities; it does not claim to reduce the total library line count.

A broader document-access wrapper produced a cleaner-looking loop but repeated path checks for get/write/reverse lookups and performed worse. Reusing collection maps for deletion simplified that loop and improved grouped deletion, but nested deletion rose from 3.280 ms to 4.884 ms in the exploratory AOT series. Shared deletion also rose from 16.846 ms to 18.556 ms.

The final candidate therefore paired the thin propagation helper with the original deletion shortcut. Even then, alternating-dependency deletion rose from 4.678 ms to 10.192 ms, with the candidate slower in all three process medians. The deletion source itself was unchanged, so the cause is not isolated. Host-load noise limits other conclusions, but it is not sufficient reason to dismiss this result and ship the refactor. No new core-library cleanup is retained.

## Headless by default

The macOS profiling runner starts a real Flutter engine with headless execution enabled. It removes the window nib from resources, uses explicit application startup, marks the host background-only and prohibits activation. The Dart entrypoint skips widgets and frame waits in this mode. Heap runs reject historical hosts that were not built headlessly.

Both JIT and release AOT probes completed successfully. An OS-level observer recorded no activation and only the prohibited activation policy; native startup also checks that the application has no windows. No screen capture or UI automation permission is needed.

The interrupted windowed exploration is excluded from these comparisons. An initial background probe caught a remaining window through its startup precondition, without taking focus; startup was corrected and both modes were rechecked before timing.

## Final comparison

Three fresh processes per variant and compilation mode, nine measured samples per operation, five warmups and a minimum 200 ms warmup phase. Process order alternates. All builds and correctness checks complete before timings. Both sides use the same headless host and workload sources; binaries and Dart artifacts are hash-checked before execution.

Before is the implementation at the start of this cleanup, already containing the previous store/propagation optimizations. Values are pooled AOT medians in milliseconds per named operation. This is a separate measurement series from the historical windowed runs, not a comparison against main.

| Operation | Retained implementation | Rejected cleanup candidate |
| --- | ---: | ---: |
| Notify 100k shared dependents | 16.901 | 19.904 |
| Notify 20k nested dependents | 3.625 | 3.459 |
| Notify 1k of 100k grouped dependents | 0.203 | 0.204 |
| Notify 10k dependents with four queries | 18.458 | 19.542 |
| Delete 100k shared dependents | 17.736 | 18.658 |
| Delete 20k nested dependents | 3.458 | 3.631 |
| Delete 100k grouped dependents | 31.876 | 34.776 |
| Delete alternating source dependencies | 4.678 | 10.192 |
| Propagate across scattered collections | 7.223 | 6.540 |
| Propagate through shared summary/cycle | 11.540 | 11.860 |
| 1k writes without dependents | 0.890 | 1.049 |
| 1k writes with one dependent each | 2.184 | 2.434 |

## Validation and limits

- 253 native/core/benchmark tests and 44 headless Chrome tests passed. Static analysis is clean. Profiling variants still configure; affected historical controls pass their core tests.
- Production library hashes match the saved starting implementation. Candidate source snapshots are retained for inspection; they are not the current production library.
- Existing dependency tests cover cycles, diamonds, unusual parent/ID boundaries, repeated broadcasts, deletion survivors and recreation. Workload result checks remain enabled in AOT.
- JIT samples, process medians and host load are archived separately. The final comparison encountered a major host-load burst (one-minute load above 60), including during candidate runs. This is not clean evidence for a small speedup or regression; retain the full process ranges. The exploration also had load bursts. Process ranges are not confidence intervals.
- macOS arm64 / Flutter 3.44.4 / Dart 3.12.2. These runs do not establish physical mobile-device performance.
