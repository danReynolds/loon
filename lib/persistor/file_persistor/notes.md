* Switch to storing resolver paths in file data stores using a value store tree rather than flat paths. Then when data is cleared, can clear all data under that path easily and if there's any data for that path anywhere else, it must be above that path in the file data store resolver tree, so clear it from all paths walking up to the root. Nice!

* Create a different kind of ref value store that keeps a ref count of the number of times a distinct value exists under a node in the store. Then deleting a node
is able to be done in O(1) time get the data stores that need to be accessed.

