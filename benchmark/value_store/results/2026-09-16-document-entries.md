# Document allocation changes and dependency entries — September 16, 2026

[Raw timing samples, heap samples and build/source receipts](2026-09-16-document-entries.json)

## Findings

**Recommendation: keep the entry model for bulk deletion.** Its 2.6–3.1× AOT
cleanup advantage remains after optimizing `fromPath`. The four small changes
are useful with either representation. Entries have a real memory cost, so this
is a throughput-versus-retention choice; a workload that rarely deletes large
subtrees may reasonably prefer the simpler path model. The current library
keeps entries. Empty-set handle retention remains a separate follow-up.

The four small changes are implemented. With the entry model held constant,
release AOT medians improved for nested document construction (14.394 → 4.138 ms
per 100k), nested `fromPath` construction (53.496 → 19.734 ms per 100k), first
document hashing (7.624 → 1.561 ms per 100k), snapshot hashing (4.285 → 1.537 ms
per 100k), and rewiring one of 32 dependencies on 1,000 documents
(4.978 → 3.944 ms). These are workload measurements of the combined changes,
not an additive attribution of savings to each edit.

Faster parsing does not eliminate the benefit of the retained-entry cleanup:

| Delete workload | Old paths | Improved paths | Improved entries | Entries speedup over improved paths |
| --- | ---: | ---: | ---: | ---: |
| 100k documents, one source | 76.932 ms | 69.140 ms | 23.956 ms | 2.89× |
| 100k documents, 100 sources | 83.177 ms | 74.356 ms | 28.453 ms | 2.61× |
| 20k nested documents | 19.371 ms | 14.221 ms | 4.571 ms | 3.11× |
| 10k documents, four queries | 6.262 ms | 5.708 ms | 2.211 ms | 2.58× |

This compares two complete cleanup strategies. Entries allow `extractValues`,
reuse existing document handles and reuse their initialized hashes. The path
strategy constructs a map of full paths, constructs document handles and hashes
those new handles. The benefit cannot be attributed to the entry class alone.

The memory cost is measurable: 100k entry wrappers occupy **3.2 MB / 3.05 MiB**
of shallow storage in this profile-AOT build. For nonempty shared-source
dependencies, the document counts match the path model before and after handle
replacement: the reverse index already retains those handles.

Empty dependency sets expose an additional retention case. When a new handle
writes the same empty dependencies, `setEquals` returns early and the entry still
holds the previous handle, while the current snapshot holds the new handle. After
replacing all 100k handles, the entry variant has 200,001 live documents versus
100,001 in the path variant, and roughly **19.2 MB / 18.31 MiB** more live heap
in this fixture, including wrappers. This is bounded retention until deletion,
not an accumulating leak on every write. Both variants release all transaction
handles after deletion; clear releases the remaining account handle. Avoiding
handles for empty dependency sets is a separate improvement, not part of these
four changes, and should preserve the current empty-versus-null API semantics.

JIT is not a substitute for AOT: for example snapshot hashing moved from
1.500 to 1.759 ms in debug JIT, while release AOT improved from 4.285 to 1.537 ms.
The recommendation should follow the production compilation mode.

## Focused notification repeat

The full run showed a possible four-query regression: 27.081 ms with improved
entries versus 22.631 ms with improved paths. This warranted a repeat rather than
assuming all notification differences were noise. The same release binaries ran
only `10k_four_queries`, with ten warmups, at least 1,000 ms warmup phase time,
21 measured trials, and three fresh processes per variant in alternating order.
These 12 extra processes are archived separately; their samples are not pooled
into the original run.

| Four-query write + delivery | Pooled median | Range of process medians |
| --- | ---: | ---: |
| Before entries | 23.387 ms | 22.656–23.738 ms |
| Before paths | 23.785 ms | 23.474–24.383 ms |
| Improved entries | 22.133 ms | 21.905–22.532 ms |
| Improved paths | 22.413 ms | 22.247–22.535 ms |

The original total-notification penalty did not reproduce. This does not prove
identical cost under every workload, but it does not support calling entries a
notification regression. Subphase timing still differs; the relevant combined
latency is close. Entry initialization was slower in the full run and faster in
this repeat, so small setup differences are also not a reliable selection basis.
Deletion remained clearly faster: 2.163 versus 5.529 ms in the focused repeat.

## Comparison

All variants retain the earlier store optimizations, document path/hash caching
and snapshotting of caller-owned dependency sets. Only this turn's four changes
and the forward dependency representation vary. No callback traversal API is used.

| Variant | Four small changes | Dependency cleanup |
| --- | --- | --- |
| document_before | Before | Retained entries + extractValues |
| document_before_paths | Before | Path map + Document.fromPath |
| combined | After | Retained entries + extractValues |
| document_paths | After | Path map + Document.fromPath |

Changes: fixed-arity hashing, cached collection paths, direct membership loops
for dependency differences, and reference-path parsing without split/join.
Document and Collection factories share the parser; generated-path checks
verify legacy separator/empty-path behavior. Persistence configuration is preserved.

## Native aot

Median milliseconds. Ranges and individual samples are in the JSON.

| Operation | Before entries | Before paths | After entries | After paths |
| --- | ---: | ---: | ---: | ---: |
| dependency/100k_100_groups/delete | 28.657 | 83.177 | 28.453 | 74.356 |
| dependency/100k_100_groups/seed | 221.856 | 213.932 | 213.358 | 203.161 |
| dependency/100k_100_groups/total | 0.658 | 0.645 | 0.690 | 0.655 |
| dependency/100k_shared/delete | 24.014 | 76.932 | 23.956 | 69.140 |
| dependency/100k_shared/seed | 219.181 | 218.268 | 218.794 | 208.347 |
| dependency/100k_shared/total | 74.164 | 73.931 | 73.159 | 70.326 |
| dependency/10k_four_queries/delete | 2.235 | 6.262 | 2.211 | 5.708 |
| dependency/10k_four_queries/seed | 16.563 | 15.931 | 15.248 | 14.690 |
| dependency/10k_four_queries/total | 24.634 | 24.303 | 27.081 | 22.631 |
| dependency/20k_nested/delete | 4.637 | 19.371 | 4.571 | 14.221 |
| dependency/20k_nested/seed | 49.741 | 48.085 | 44.464 | 43.846 |
| dependency/20k_nested/total | 19.562 | 18.870 | 20.383 | 19.771 |
| documents/construct/flat_100k | 6.785 | 7.414 | 6.253 | 6.639 |
| documents/construct/nested_100k | 14.394 | 14.518 | 4.138 | 4.350 |
| documents/from_path/nested_100k | 53.496 | 55.259 | 19.734 | 20.576 |
| documents/hash/first_document_100k | 7.624 | 7.462 | 1.561 | 1.554 |
| documents/hash/snapshot_100k | 4.285 | 4.335 | 1.537 | 1.545 |
| documents/rewire/1k_docs_32_dependencies_one_changed | 4.978 | 4.974 | 3.944 | 3.778 |

## Native jit

Median milliseconds. Ranges and individual samples are in the JSON.

| Operation | Before entries | Before paths | After entries | After paths |
| --- | ---: | ---: | ---: | ---: |
| dependency/100k_100_groups/delete | 27.821 | 71.178 | 26.902 | 66.588 |
| dependency/100k_100_groups/seed | 204.771 | 204.833 | 202.543 | 202.046 |
| dependency/100k_100_groups/total | 0.730 | 0.716 | 0.704 | 0.770 |
| dependency/100k_shared/delete | 24.174 | 63.041 | 23.954 | 57.809 |
| dependency/100k_shared/seed | 208.429 | 206.803 | 201.160 | 205.150 |
| dependency/100k_shared/total | 80.669 | 77.682 | 74.322 | 79.740 |
| dependency/10k_four_queries/delete | 2.699 | 5.249 | 2.320 | 5.178 |
| dependency/10k_four_queries/seed | 15.061 | 15.395 | 12.719 | 13.648 |
| dependency/10k_four_queries/total | 26.647 | 25.335 | 24.339 | 24.417 |
| dependency/20k_nested/delete | 4.757 | 18.484 | 5.210 | 12.647 |
| dependency/20k_nested/seed | 43.968 | 43.112 | 43.716 | 41.879 |
| dependency/20k_nested/total | 20.243 | 23.137 | 21.004 | 19.587 |
| documents/construct/flat_100k | 7.493 | 7.082 | 6.714 | 7.877 |
| documents/construct/nested_100k | 14.273 | 13.224 | 6.453 | 7.133 |
| documents/from_path/nested_100k | 53.657 | 50.670 | 22.102 | 21.718 |
| documents/hash/first_document_100k | 6.560 | 6.128 | 3.417 | 3.635 |
| documents/hash/snapshot_100k | 1.500 | 1.518 | 1.759 | 1.766 |
| documents/rewire/1k_docs_32_dependencies_one_changed | 3.460 | 3.402 | 2.394 | 2.412 |

## Live heap in separate profile builds

Medians over three fresh processes per representation. Class bytes are shallow
instance storage, not dominator retained sizes. Isolate heap deltas include
measurement/runtime noise; each delta uses that shape's empty baseline.

| Shape / phase | Entry objects | Documents (entries / paths) | Extra entry shallow MiB | Live heap delta MiB (entries / paths) |
| --- | ---: | ---: | ---: | ---: |
| one_shared_source/seeded | 100000 | 200001 / 200001 | 3.05 | 64.47 / 61.42 |
| one_shared_source/handles_replaced | 100000 | 300001 / 300001 | 3.05 | 79.73 / 76.67 |
| one_shared_source/deleted | 0 | 1 / 1 | 0.00 | 0.02 / 0.02 |
| one_shared_source/cleared | 0 | 0 / 0 | 0.00 | 0.02 / 0.02 |
| empty_dependencies/seeded | 100000 | 100001 / 100001 | 3.05 | 39.57 / 36.52 |
| empty_dependencies/handles_replaced | 100000 | 200001 / 100001 | 3.05 | 54.83 / 36.52 |
| empty_dependencies/deleted | 0 | 1 / 1 | 0.00 | 0.01 / 0.01 |
| empty_dependencies/cleared | 0 | 0 / 0 | 0.00 | 0.01 / 0.01 |

## Method and validation

- Flutter 3.44.4, Dart 3.12.2, macOS arm64.
- Four variants × two timing modes × two suites × three fresh-process passes: 48 timing processes.
- A focused AOT notification repeat adds 12 fresh processes and 63 samples per variant, archived separately.
- Eleven measured trials per operation per process, 33 per operation per runtime/variant. At least five warmups and 500 ms warmup phase time.
- Variant/mode/suite order reverses on alternate passes. Method order reverses for document construction cases.
- All builds and 145 core/benchmark checks per copied variant finish before timing. Workload checks stay active in release.
- Constructor outputs escape and are validated after timing. Dependency workloads use actual Loon APIs; seed, write/delivery and deletion are separate metrics.
- Heap runs use the VM service in separate instrumented AOT processes. Retention scenarios include replacing every document handle without changing dependencies.
- Host load is recorded. Small differences need caution; ranges are not confidence intervals. No mobile-device qualification.
- Measured Dart sources matched the workspace when this report was captured.
  Subsequent cleanup moved the unchanged path parser into `lib/utils/store.dart`,
  folded its regression tests into `loon_test.dart`, and exposed the existing
  nested workload through the runner's `--case` option. The recorded hashes and
  samples remain those of the measured snapshot.

## Reproduction

```sh
dart run benchmark/value_store/run.dart --variants document_before,document_before_paths,combined,document_paths --suites documents,dependency --passes 3 --trials 11 --warmups 5 --warmup-ms 500
dart run benchmark/value_store/run.dart --out build/value_store_profiles/new-heap --variants combined,document_paths --suites documents --modes profile --build-only
dart run benchmark/value_store/run_retention.dart build/value_store_profiles/new-heap
# Reproduce the focused notification workload; the recorded repeat reused the existing binaries.
dart run benchmark/value_store/run.dart --variants document_before,document_before_paths,combined,document_paths --suites dependency --modes aot --case 10k_four_queries --passes 3 --trials 21 --warmups 10 --warmup-ms 1000
```
