ComputableDocument/ComputableQuery still run into an issue because they need to wait for the async broadcast before being able to get the updated value.

A query, for example, waits for the broadcast and then recomputes itself.

If we were to access a downstream computable of the query after the write but before the broadcast then it would be stale.

If it's a direct ComputableQuery it's fine since accessing it re-calculates it. But not for downstreams, since they don't know that it needs to.

