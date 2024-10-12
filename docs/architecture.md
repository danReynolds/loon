# Loon

## Data Layer

Loon stores collections of documents. Documents can have nested subcollections, which are modeled using a document tree structure.

```dart
final messageDoc = Loon.collection('users').doc('1').subcollection('messages').doc('1');
messageDoc.create('Hello');
```

In this example, a user message is stored under its associated user in the document tree. The data is modeled as a tree data structure that groups values under a given path, enabling quick access to all values of a particular collection. Given the example above, the `ValueStore` representation is shown below:

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

Each observable (`ObservableDocument`, `ObservableQuery`) implements the `BroadcastObserver` interface, and are stored in a set of broadcast observers
on the `BroadcastManager`.

When changes occur to documents in the store, the change event such as a `BroadcastEvents.added`, `BroadcastEvents.modified` or `BroadcastEvents.removed`
event, is recorded in the broadcast tree, which is another instance of a `ValueStore`.

All changes that occur in the same task of the event loop are batched into the current broadcast tree and are scheduled to be processed asynchronously by the broadcast observers. The handing off of the batched change events to each broadcast observer for processing is called the *broadcast*.

On broadcast, each broadcast observer checks if it is affected by any of the changes in the current broadcast.

* For an `ObservableDocument`, this involves checking if the broadcast tree contains an event for itself.
* For an `ObservableQuery`, this involves iterating through the changes at its collection path in the broadcast tree
  and determining if any of those changes affect its result set. The complexity of this check scales with the size of the *changes* to its collection, rather than the size of the query's existing result set.

If the broadcast observer has changes, then it emits its updated data to its listeners.

### Dependencies

Documents can specify that they depend on other documents and that they should react to changes to those documents.

```dart
Loon.collection(
  'posts',
  dependenciesBuilder: (postSnap) {
    return {
      Loon.collection('users').doc(postSnap.data.userId),
    };
  },
);
```

In this example, each post specifies that it has a dependency on its associated user. This means that when a post's user changes,
any observers of the post, such as an `ObservableDocument` for that specific post or an `ObservableQuery` that currently includes
that post in its list of documents, should also notify its listeners.

If a post is displayed alongside its user's profile picture, then without dependencies the code for the post would need to observe
both the post and user document for changes separately. With dependencies, it only needs to observe the post and the post will react to any changes to the user automatically.

Document dependencies are modeled using a `ValueStore` for indexing a document's dependencies by path, and a flat map of documents to their set of dependents.

```dart
final dependenciesStore = ValueStore<Set<Document>>();
final Map<Document, Set<Document>> dependentsStore = {};
```

When a document is updated, it iterates through its set of dependents and marks each of them for broadcast with a `BroadcastEvent.touched` event.

When a document or collection is deleted, each broadcast observer with dependencies checks to see if the deleted path is present in its dependency tree and if it is, then the broadcast observer notifies its listeners.

Each broadcast observer has its own cached dependency tree which maintains a ref count of the number of times a path exists in the tree using the `PathRefStore`. When a path's ref count goes to 0, it is removed from the tree. This ref store is used to determine if a deleted path exists in an observer's dependencies.

## Persistence Layer

Loon comes with a default `FilePersistor` implementation. To enable persistence, clients call to `configure()` with the persistor as shown below:

```dart
Loon.configure(persistor: FilePersistor());
```

By default, the `FilePersistor` serializes and persists all documents in a single `__store__.json` file.

Non-primitive collections (not a string, bool, number) must specify a fromJson/toJson serialization implementation:

```dart
class UserModel {
  final String name;

  UserModel({
    required this.name,
  });

  factory UserModel.fromJson(Json json) {
    return UserModel(name: json['name']);
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
    };
  }

  static Collection<UserModel> get store {
    return Loon.collection<UserModel>(
      'users',
      fromJson: UserModel.fromJson,
      toJson: (user) => user.toJson(),
    );
  }
}
```

The `FilePersistor` extends a base `Persistor` class that automatically handles throttling and synchronization of the four types of persistence operations:

```dart
/// Persist function called with the bath of documents that have changed (including been deleted) within the last throttle window
/// specified by the [Persistor.persistenceThrottle] duration.
Future<void> persist(List<Document> docs);

/// Hydration function called to read data from persistence. If no entities are specified,
/// then it hydrations all persisted data. if entities are specified, it hydrates only the data from
/// the paths under those entities.
Future<HydrationData> hydrate([List<StoreReference>? refs]);

/// Clear function used to clear all documents in a collection.
Future<void> clear(Collection collection);

/// Clears all documents and removes all persisted data.
Future<void> clearAll();
```

Any custom persistor can be implemented using just these four operations. In the case of the `FilePersistor`, it packages each of these operations
into messages that it sends to the `FilePersistorWorker` running on a background isolate.

The worker receives these persistence operation messages from the main isolate and passes them off to the [FileDataStoreManager] for processing. The `FileDataStoreManager` maintains a set of hydrated `FileDataStore` objects, which map 1:1 between persistence keys and file stores and are responsible for hydrating and persisting documents to and from their associated files.

Individual collections can customize their persistence file by specifying a persistor key:

```dart
class UserModel {
  final String name;

  UserModel({
    required this.name,
  });

  factory UserModel.fromJson(Json json) {
    return UserModel(name: json['name']);
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
    };
  }

  static Collection<UserModel> get store {
    return Loon.collection<UserModel>(
      'users',
      fromJson: UserModel.fromJson,
      toJson: (user) => user.toJson(),
      settings: FilePersistorSettings(
        key: FilePersistor.key('users'),
      ),
    );
  }
}
```

In the above example, the users collection has specified that all user documents should be stored in a separate `FileDataStore` and persisted
to a file named after its key called `users.json`. 

File persistence can be specified even more granularly at the individual document-level using a `FilePersistor.keyBuilder`:

```dart
class UserModel {
  final String name;

  UserModel({
    required this.name,
  });

  factory UserModel.fromJson(Json json) {
    return UserModel(name: json['name']);
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
    };
  }

  static Collection<UserModel> get store {
    return Loon.collection<UserModel>(
      'users',
      fromJson: UserModel.fromJson,
      toJson: (user) => user.toJson(),
      persistorSettings: FilePersistorSettings(
        key: FilePersistor.keyBuilder(
          (snap) => 'users_${snap.id}',
        ),
      ),
    );
  }
}
```

Documents with a `keyBuilder` recalculate their resolved persistence key whenever they are updated. If the resolved persistence key of an existing document changes, then the document and its subcollections (provided they don't specify their own persistence key) will be moved from the previous file store to the one specified by its updated key.

This level of persistence granularity is done to support features like sharding of large collections across multiple files (like breaking one big messages collection into `messages_shard_1`, `messages_shard_2`, etc) and grouping of small subcollections into the same file (like grouping subcollections of posts with document paths `posts__1__reactions__2`, `posts__2__reactions__1`, etc into one large reactions file).

Since any given collection can be spread across multiple `FileDataStore` objects, the `FileDataStoreResolver` is used to lookup the set of files that contain data for a given store path. The `FileDataStoreResolver` uses a variant of the `ValueStore` implementation called a `ValueRefStore` which extends `ValueStore` with ref counting
of the values that exist under a given path.

To illustrate how this works, consider the case of hydrating a users collection that is spread across multiple files in the format `users_1`, `users_2`, ... using a `FilePersistor.keyBuilder`.

The file data store resolver would look like the following:

```dart
{
   "__refs": {
    "users_1": 3,
    "users_2": 1,
  },
  "users": {
    "__refs": {
      "users_1": 3,
      "users_2": 1,
    },
    "__values": {
      "1": "users_1",
      "2": "users_1",
      "3": "users_1",
      "4": "users_2",
    }
  }
}
```

Each node of the resolver contains a ref count of the values that exist under its path in the tree. Because the number of files should be small (assumption that storing data across 100s is files is an edge case not desirable for users), the references at each node will also be small and the benefit of being able to quickly resolve the set of stores that exist under a given path is currently thought to be worth the memory trade-off.

The resolver persists this mapping to a `__resolver__.json` file that is hydrated automatically when the `FilePersistor` is initialized.

Here's a full example of how it all comes together. In this scenario, the client has specified to hydrate **just** the `users` collection by calling `hydrate()` with a collection path.

```dart
Future<void> main() async {
  await Loon.hydrate([Loon.collection('users')]);
  ...
  runApp(...);
}
```

When the hydration operation for the users collection is executed, the `FilePersistor` sends a `hydrate` message for the given collection to the `FilePersistorWorker` on the background isolate.

The worker parses the message and tells the `FileDataStoreManager` to hydrate all `FileDataStore` objects containing data for the given collection. The manager uses the `FileDataStoreResolver` to look up all of the file key refs for the `users` collection and immediately finds two values: `users_1` and `users_2`.

The `FileDataStoreManager` then iterates over each resolved `FileDataStore` and hydrates its file from disk. The manager returns only the subset of paths requested by the hydration call to the `FileDataStoreWorker`, which packages it into a message and sends its response back to the `FilePersistor` on the main isolate.

The documents are then written into the Loon document store on the main isolate and broadcast to observers.


