# Loon

## Data Layer

Loon stores collections of documents. Documents can have nested subcollections, which are modeled using a document tree structure.

```dart
final messageDoc = Loon.collection('users').doc('1').subcollection('messages').doc('1');
messageDoc.create('Hello');
```

In this example, a user message is stored under its associated user in the document tree. This data structure is a variant of a trie that groups values under a given path, a helpful optimization for quick access to all values of a particular collection. Given the example above, the [ValueStore] representation is shown below:

```dart
{
  "users": {
    "1": {
      "messages": {
        "__values": {
          "1": "Hello"
        }
      }
    }
  }
}
```

Each node in the tree is a path segment which contains the paths to its direct children as well as a `__values` key which stores all the values at that node.

Accessing data from the store involves walking down the given path and returning its associated value in the document [ValueStore].

## Reactivity Layer

Documents, collections, and queries (which consist of filters applied to a collection) can all be observed for changes.

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
event, is recorded in a broadcast tree, which is another instance of a [ValueStore].

All changes that occur in the same task of the event loop are batched into the current broadcast tree and are scheduled to be processed by broadcast observers
as part of the next micro-task. The handing off of the batched change events to each broadcast observer for processing is called the *broadcast*.

On broadcast, each broadcast observer checks if it is affected by any of the changes in the current broadcast.

* For an [ObservableDocument], this involves checking if the broadcast tree contains an event at its current path.
* For an [ObservableQuery], this involves iterating through the changes at its path in the broadcast tree for each of the documents in its collection
  and recalculating whether it needs to inform listeners of any additions, removals or updates to its documents.

### Dependency Layer

Loon has support for creating relationships between documents:

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

In this example, each post specifies that it has a dependency on its associated user. This means that when a post's associated user changes,
any observers of the post, meaning an [ObservableDocument] for that specific post or an [ObservableQuery] that currently includes that post in its list of documents, must also be rebroadcast to listeners.

This is an important feature, since otherwise if a client was observing changes to a post, it would need to wire up multiple streams for both the post, its user,
maybe some messages, and any other related data to the post. Dependencies make this much simpler, since now only the post can be observed and it will be rebroadcast
when its dependencies change.

Supporting this feature requires an additional dependency layer. 

The dependencies of documents are stored in a map on the [BroadcastManager] along with 