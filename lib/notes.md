* Need to be smart about knowing whether a broadcast observer is dirty. Use a ValueStore of clean broadcast observers by the observer's path. That way, when a change comes in for
  a particular collection, it removes all clean observers for that collection in the value store, meaning they are now dirty.

* Handles deletes too since it would just clear the entire subtree for that path.

* When an observable query is accessed, it will know if it's dirty by checking if it exists in the clean tree. If it doesn't then it recalculates, caches that value, and then reinserts itself into the clean observer value store.

* On broadcast, if an observer is not dirty, then it doesn't even need to recompute its value.

* After each broadcast, the clean value store is rebuilt, which is just O(n) insertions, where n is the number of broadcast observers, a small number.

## What about dependencies?

Do as is, when a document is deleted, iterate through the set of *clean* observers with dependencies and if they depend on the deleted path, then mark them for deletion.




