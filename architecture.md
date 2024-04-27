# Loon

## Data Layer

[Talk about how document snapshots are stored in the value store.]

## Reactivity Layer

Loon stores collections of documents. Documents, collections, and queries (which consist of filters applied to a collection)
can all be observed by clients through the [ObservableDocument] and [ObservableQuery] interface.

An example of each is shown below:

```dart
// Observable document
Loon.collection('users').doc('1').stream();
// Observable collection (technically an observable query with no filters)
Loon.collection('users').stream();
// Observable query
Loon.collection('users').where((snap) => snap.data.name == 'Luke Skywalker').stream();
```

### Broadcasts

Each type of observable ([ObservableDocument], [ObservableQuery]) implements the [BroadcastObserver] interface, and are stored in a set of broadcast observers
on the [BroadcastManager].

When changes occur to documents in the store, the change event, such as an [EventTypes.added], [EventTypes.modified] or [EventTypes.removed]
event, is recorded in a custom broadcast tree structure called a [CollectionStore], which is maintained by the [BroadcastManager] and maps document paths to changes.

A [CollectionStore] is a variant of a trie data structure that groups values by collection, a helpful optimization for quick access to all values of a particular collection. An example is shown below:

```dart
final store = CollectionStore<String>();

store.write('users__1', 'User 1');
store.write('users__2', 'User 2');
store.write('users__1__messages__2', 'Hey there!');

print(store.inspect());
<!-- {
  "users": {
    "__values": {
      "1": "User 1",
      "2": "User 2",
    },
    "1": {
      "messages": {
        "__values": {
          "2": "Hey there!",
        },
      },
    },
  }
} -->
```

All changes that occur in the same task of the event loop are batched into the current broadcast tree and are scheduled to be processed by broadcast observers
as part of the next micro-task. The handing off of the batched change events to each broadcast observer for processing is called the *broadcast*.

On broadcast, each broadcast observer checks if it is affected by any of the changes in the current broadcast.

* For an [ObservableDocument], this involves just checking if the broadcast tree contains an event at its current path.

* For an [ObservableQuery], this involves iterating through the changes at its path in the broadcast tree for each of the documents in its collection
  and recalculating whether it needs to inform listeners of any additions, removals or updates to its documents.

### Dependency Layer

Loon has support for creating relationships between documents in the reactivity layer:

```dart
Loon.collection(
  'posts',
  dependenciesBuilder: (postSnap) {
    return {
      Loon.collection('users').doc(postSnap.data.userId)),
    };
  },
);
```

In this example, we're declaring that a post has a dependency on its associated user. This means that when a post's associated user changes,
any observers of the post, meaning an [ObservableDocument] for that specific post or an [ObservableQuery] that currently includes that post in its list of documents, must also be rebroadcast to listeners.

This is an important feature, since otherwise if a client was observing changes to a post, it would need to wire up multiple streams for both the post, its user,
maybe some messages, and any other related data to the post. Dependencies make this much simpler, since now only the post can be observed and it will be rebroadcast
when its dependencies change.

Supporting this feature requires an additional dependency layer. 

The dependencies of documents are stored in a map on the [BroadcastManager] along with 