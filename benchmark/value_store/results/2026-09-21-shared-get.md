# Shared typed getter — September 21, 2026

[Raw samples, source snapshots and receipts](2026-09-21-shared-get.json)

## Decision

Use `_getParent()` in `get()`, joining `hasPath()`, `_getNode()`, `extract()`
and `extractValues()` on the same typed traversal. The getter is now six lines
and its separate scanning loop is removed. The baseline is the uncommitted typed
parent cleanup, not `main` or the enum-based committed implementation; the saved
sources isolate this getter change.

```dart
T? get(String path) {
  if (_getParent(path) case (final parent, final segment)) {
    return parent[_values]?[segment];
  }
  return null;
}
```

Mutation traversal still creates/prunes nodes or maintains reference counts;
nearest-ancestor search visits ancestors. Those are different operations, and this
experiment does not introduce flags or callbacks to force them into a read helper.

## Focused comparison

Standalone Dart JIT and AOT only: two fresh processes per variant/runtime, seven
measured trials, three warmups and at least 80 ms of warmup phase time. Process
order reverses on the second pass. Seventeen filtered operations cover hits,
misses, empty stores, path shapes and unchanged related lookup controls. Fixtures
and correctness checks are outside timing. Builds and measured runs took about
24 seconds combined; no Flutter hosts were built or launched.

Milliseconds per named batch, pooled AOT medians:

| Operation | Dedicated getter | Shared getter |
| --- | ---: | ---: |
| 20k shallow reads | 1.659 | 1.635 |
| 20k deep reads | 4.595 | 4.588 |
| 100k deep early misses | 2.777 | 2.782 |
| 100k deep late misses | 21.848 | 22.423 |
| 100k shallow late misses | 7.450 | 7.694 |
| 10k UUID-path reads | 2.962 | 2.943 |
| 10k Unicode-path reads | 4.253 | 4.213 |
| 100k reads from an empty store | 0.211 | 0.230 |

AOT hits are comparable; late misses take roughly 3% longer. Empty reads show
about 9% more time, but only 0.019 ms per 100k calls. In JIT, deep/UUID/underscore
hit batches are roughly 4–6% slower, while shallow hits and early misses are
comparable. This focused screen supports preferring reuse, not a universal
speedup claim. It does not establish whether the compiler eliminates records.

One-minute host load stayed around 4–5. Individual outliers remain in the raw
samples; two process medians are not confidence intervals. This is macOS arm64
Dart 3.12.2 evidence, not a complete Flutter-engine or mobile-device comparison.

## Validation and workflow

All 28 store tests passed, including random mutation/reference-count checks,
nullable values, unusual delimiters and extraction semantics. Analysis of the
changed files is clean. Full PR validation remains deferred until the PR settles.

`run_core.dart --filter REGEX` now selects individual store operations, records
the selection in its manifest and skips unrelated measurements. Shared fixture
construction still runs. Missing/empty reads were added to the workload for this
comparison. A fail-fast check for an empty selection was added after measurement;
it runs outside all timed intervals. The archive retains the measured workload.
