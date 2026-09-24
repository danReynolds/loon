# Performance decisions

The performance decisions behind the value store and the dependency and broadcast managers, newest
first. Raw samples for the entries up to 2026-09-21 are in the history of PR #42. Fetch it with
`git fetch origin pull/42/head`, then run, for example, `git show 5efc2e6:benchmark/value_store/results/`.

## 2026-09-24: Touch dependents without clearing their document observers

The propagation benchmark wrote observer values at the dependents' and collections' own paths, so the
first collection clear emptied the store and every later clear returned at once, and the 2026-09-22
one-collection numbers left out the cost of clearing observer values. With values keyed under the
observed paths, as observers key them, touching 20k dependents in one collection took 16.5 ms in AOT
`manager_core`, most of it clearing observer values.

A touch doesn't change a dependent's data, so its document observers keep their cached snapshots, and
only its collection's cached query results are cleared, once per collection. For 20k dependents:

- Without the document clears: 16.5 → 9.0 ms in one collection, and 22.3 → 15.1 ms across 5,000.
- Then clearing each collection once: 9.1 → 5.2 ms in one collection, and 14.8 → 11.0 ms across
  5,000 interleaved collections. Skipping only consecutive repeats matched the set in one collection
  but didn't help interleaved dependents. The set costs 30–80 ns per fan-out of one or two dependents.

## 2026-09-24: Settle the heap before manager samples

Setup left tens of thousands of young objects that collections during the timed operation copied, so
builds with the same algorithm differed by up to 24% on the 5,000-collection propagation cases, in
either direction. Each `manager_core` sample now starts after `settleHeap()` promotes what its setup
allocated. The same builds then agreed within 3–7%, as they did with a 512 MB young generation.

## 2026-09-24: Write events in one lookup

`writeDocument` writes an event directly, or with `putIfAbsent` for a touch, instead of reading the
pending event first: 20k writes without dependents took 31–35% less time in AOT `manager_core`
(3.9 → 2.7 ms), and chained writes 3–15% less. Merging the store's two parent lookups into one
`_getParent` was neutral in `store_core` over 7 passes, with a 15-pass recheck of overwrites.
`extractValues` collects through `forEachValue`, with no measurable difference.

## 2026-09-24: Deletes through the parent cache (not adopted)

Deletes that reused the cached parent, and kept it while the node stayed in the tree, took 22–53% less
time deleting 20k siblings in `store_core`, with no cost on scattered deletes. They didn't change
propagation once touches stopped clearing document observers, so they're left for bulk-delete work.

## 2026-09-23: Visit deleted dependency entries in place

Deleting a collection unlinks its documents from their dependencies' reverse indexes while visiting
their entries with `ValueStore.forEachValue`, instead of extracting the entries into a set first.
For 20k records in AOT `manager_core`, it takes 32–37% less time: 2.8 vs 4.5 ms when they share one
dependency, and 5.5 vs 8.2 ms when each has its own.

## 2026-09-23: Keep the parent cache in the value store

Moving the last-parent state into a helper class was slower on the store's hot paths: empty-store
gets took about 25% longer, and early misses and plain writes a few percent longer. It stays as
three fields and two helpers in `_BaseValueStore`.

## 2026-09-22: Reuse the last parent node in the value store

Sending dependent touches through `writeDocument` read well, but made propagation to 20k dependents in
one collection about 6× slower: 2.7 → 16.2 ms in AOT `manager_core`.

`_BaseValueStore` now remembers the last parent node it resolved. Reads and writes under the same
parent reuse it, and every operation that removes nodes forgets it. `ValueStore.putIfAbsent` records a
touch in one call. This replaced the manager's own collection-map cache.

AOT, against sending touches through `writeDocument`:

- Propagation to 20k dependents: 16.2 → 4.9 ms in one collection, 15.4 → 10.1 ms across 5,000.
- 20k writes without dependents: 4.4 → 3.8 ms. Store reads and writes under one parent take 40–80%
  less time.
- Costs: about 5% on early misses and deletes, and 12% on reads that never share a parent.
- A 2- or 4-entry cache only helped writes that alternate between deep collections that fit in it
  (about 15%), and cost 13–30% on scattered access. One entry was kept.

## 2026-09-22: Read query snapshots by collection

`ObservableQuery` reads a broadcast's snapshots with one `getChildValues` call and caches them by
document ID, instead of building a `Document` per event. It is about 2× faster with 20k changed
documents (JIT). Snapshots that aren't parsed yet, such as hydrated data, still go through
`Document.get`.

## 2026-09-21: Insert-if-absent primitives (not adopted)

A single-walk insert-if-absent took about 46% less time for repeated insertion, and grouped bulk
inserts 74% less. Propagation built on them lost to collection-map reuse on dense fan-out, and bulk
batching changed query ordering. Superseded by the value store's parent reuse.

## 2026-09-21: Collection-map helper (not adopted)

A `_CollectionValues` helper and a document-access wrapper read better, but repeated path checks and
slowed deletion: alternating-dependency deletion went from 4.7 to 10.2 ms. The engine stayed as it was.

## 2026-09-21: Typed parent lookup and shared getter

One `(Map, String)? _getParent(path)` helper replaced the access-mode enum, and `get()` uses it too.
`ValueRefStore` shares one `_subtractRef` helper. The existing pruning stayed after two simpler
versions cost more.

## 2026-09-20: Scoped dependency propagation

Propagation reused the last collection map of the event store and the reverse index during one
synchronous walk, taking about 71% and 81% less time for shared and nested propagation. Deletion
reused the last dependency set. Replaced on 2026-09-22 by the value store's parent reuse.

## 2026-09-20: Parsed-path caches (not adopted)

Parsed paths kept on document handles made reads about 40% faster but cost 14–29 MB per 100k handles.
Bounded shared caches only helped when the working set fit, and a one-entry recent-path cache didn't
help. The store kept its scanner.

## 2026-09-20: Store core pass and delimiter scanning

`hasPath` resolves in one walk, extraction gets the owning node and final segment together, traversal
uses `Map.forEach` and stops at leaf buckets, and a code-unit delimiter scanner replaced
multi-character `indexOf`. No node cache, flat index or new API was added.

## 2026-09-16: Document allocation and dependency entries

Adopted fixed-arity `Object.hash`, cached collection paths, membership loops instead of temporary
difference sets, and reference-path parsing without splitting and rejoining. Retained
`_DependencyEntry` handles stayed over rebuilding documents from paths: 2.6–3.1× faster bulk-deletion
cleanup in AOT, at a memory cost.

## 2026-09-15: Traversal and extraction APIs (not adopted)

Callbacks, lazy iterables, hand-written iterators and shared bucket extraction had no consistent
winner. A lazy iterator took about twice as long as a callback for simple sums in AOT, and extraction
cost is mostly building the result set. `extractValues` stayed, with no public traversal API.

## 2026-09-15: First store pass

`get` walks segments incrementally and returns early on an empty store, empty-store deletes skip
work, and `Document` caches its path and hash.
