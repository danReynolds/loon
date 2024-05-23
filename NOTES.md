

ObservableQuery keeps track of a version integer that gets set on a per collection basis. Whenever a query pending broadcast is accessed with get(),
it checks the last version that it has processed. If its version is the same as the current broadcast version for that collection, then
it can skip processing the broadcast.

It caches its changeSnaps until the broadcast goes out.