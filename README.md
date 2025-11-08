# Loon

<img src="https://github.com/danReynolds/loon/assets/2192930/8d03dc8f-9d43-4b7e-951d-5e54ec857897" width="300" height="300">
<br />
<br />

<table border="1">
  <tr>
    <th>Android</th>
    <th>iOS</th>
    <th>Web</th>
    <th>macOS</th>
  </tr>
  <tr>
    <td>✅</td>
    <td>✅</td>
    <td>✅</td>
    <td>✅</td>
  </tr>
</table>

<br />

Loon is a reactive document data store for Flutter.

## Features

* Synchronous reading, writing and querying of documents.
* Streaming of changes to documents and queries.
* Out of the box persistence and encryption.

## Install

```dart
flutter pub add loon
```

## ➕ Creating documents

Loon makes it easy to work with collections of documents.

```dart
import 'package:loon/loon.dart';

Loon.collection('users').doc('1').create({
  'name': 'John',
  'age': 28,
});
```

Documents are stored under collections in a tree structure. They can contain any type of data, like a `String`, `Map` or typed data model:

```dart
import 'package:loon/loon.dart';
import './models/user.dart';

Loon.collection<UserModel>(
  'users',
  fromJson: UserModel.fromJson,
  toJson: (user) => user.toJson(),
).doc('1').create(
  UserModel(
    name: 'John',
    age: 28,
  )
);
```

If persistence is enabled, then a typed collection needs to specify a `fromJson/toJson` serialization pair. In order to avoid having to specify types or serializers whenever a collection is accessed, it can be helpful to store the collection in a variable or as an index on the data model:

```dart
class UserModel {
  final String name;
  final int age;

  UserModel({
    required this.name,
    required this.age,
  });

  static final Collection<UserModel> store = Loon.collection(
    'users',
    fromJson: UserModel.fromJson,
    toJson: (user) => user.toJson(),
  );
}
```

Documents can then be read/written using the index:

```dart
UserModel.store.doc('1').create(
  UserModel(
    name: 'John',
    age: 28,
  ),
);
```

## 📚 Reading documents

```dart
final snap = UserModel.store.doc('1').get();

if (snap != null && snap.data.name == 'John') {
  print('Hi John!');
}
```

Reading a document returns a `DocumentSnapshot?` which exposes a document's data and ID:

```dart
print(snap.id) // 1
print(snap.data) // UserModel(...)
```

To watch for changes to a document, you can listen to its stream:

```dart
UserModel.store.doc('1').stream().listen((snap) {});
```

You can then use Flutter's built-in `StreamBuilder` or the library's `DocumentStreamBuilder` widget to access data from widgets:

```dart
class MyWidget extends StatelessWidget {
  @override
  build(context) {
    return DocumentStreamBuilder(
      doc: UserModel.store.doc('1'),
      builder: (context, snap) {
        final user = snap?.data;

        if (user == null) {
          return Text('Missing user');
        }

        return Text('Found user ${user.name}');
      }
    )
  }
}
```

## 𖢞 Subcollections

Documents can be nested under subcollections. Documents in subcollections are uniquely identified by the path to their collection and
their document ID.

```dart
final friendsCollection = UserModel.store.doc('1').subcollection('friends');

friendsCollection.doc('2').create(UserModel(name: 'Jack', age: 17));
friendsCollection.doc('3').create(UserModel(name: 'Brenda', age: 40));
friendsCollection.doc('4').create(UserModel(name: 'Bill', age: 70));

final snaps = friendsCollection.get();

for (final snap in snaps) {
  print("${snap.data.name}: ${snap.path}");
  // Jack: users__1__friends__2
  // Brenda: users__1__friends__3
  // Bill: users__1__friends__4
}
```

## 🔎 Queries

Documents can be filtered using queries:

```dart
final snapshots = friendsCollection.where((snap) => snap.data.name.startsWith('B')).get();
for (final snap in snapshots) {
  print(snap.data.name);
  // Brenda
  // Bill
}
```

Queries can also be streamed, optionally using the `QueryStreamBuilder`:

```dart
class MyWidget extends StatelessWidget {
  @override
  build(context) {
    return QueryStreamBuilder(
      query: UserModel.store.where((snap) => snap.data.age >= 18),
      builder: (context, snaps) {
        return ListView.builder(
          itemCount: snaps.length,
          builder: (context, snap) {
            return Text('${snap.data.name} is old enough to vote!');
          }
        )
      }
    )
  }
}
```

## ✏️ Updating documents

Assuming a model has a `copyWith` function, documents can be updated as shown below:

```dart
final doc = UserModel.store.doc('1');
final snap = doc.get();

doc.update(snap.data.copyWith(name: 'John Smith'));
```

The reading and writing of a document can be combined using the `modify` API.

```dart
UserModel.store.doc('1').modify((snap) {
  return snap.data.copyWith(name: 'John Smitherson');
});
```

## ❌ Deleting documents

Deleting a document removes it and all of its subcollections from the store.

```dart
UserModel.store.doc('1').delete();
```

## 🌊 Streaming changes

Documents and queries can be streamed for changes which provides the previous and current document data as well as the event type of the change:

```dart
UserModel.store.streamChanges().listen((changes) {
  for (final changeSnap in changes) {
     switch(changeSnap.event) {
      case BroadcastEvents.added:
        print('New document ${changeSnap.id} was added to the collection.');
        break;
      case BroadcastEvents.modified:
        print('The document ${changeSnap.id} was modified from ${changeSnap.prevData} to ${changeSnap.data}.');
        break;
      case BroadcastEvents.removed:
        print('${changeSnap.id} was removed from the collection.');
        break;
      case BroadcastEvents.hydrated:
        print('${changeSnap.id} was hydrated from the persisted data.');
        break;
    }
  }
});
```

## 🔁 Data Dependencies

Data relationships in the store can be established using the data dependencies builder.

```dart
class PostModel {
  final String message;
  final String userId;

  PostModel({
    required this.message,
    required this.userId,
  })
}

final posts = Loon.collection<PostModel>(
  'posts',
  dependenciesBuilder: (snap) {
    return {
      UserModel.store.doc(snap.data.userId),
    };
  },
);
```

In this example, whenever a post's associated user is updated, the post will also be rebroadcast to its active listeners.

Additionally, whenever a document is updated, it will rebuild its set of dependencies, allowing documents to support dynamic dependencies
that can change in response to updated document data.

## 🪴 Root collection

Not all documents necessarily make sense to be grouped together under any particular collection. In this scenario, any one-off documents can be stored
on the root collection:

```dart
Loon.doc('current_user_id').create('1');
```

## 🗄️ Data Persistence

Persistence is supported on both web and native platforms. It works out of the box and can be configured on app start.

*Native* platforms (iOS, Android, macOS) use a default file-based persistence implementation, while *web* persists data to IndexedDB.

The currently available persistence options are broken down by platform:

### Native

* **SqlitePersistor**: A SQLite persistence implementation using [sqflite](https://pub.dev/packages/sqflite). Documents are distributed in rows based on their persistence configuration.
* **FilePersistor**: A file-based persistence implementation for native platforms. Documents are stored in one or more files based on the persistence configuration.

### Web

* **IndexedDBPersistor**: The default persistence implementation for web platforms. Documents are stored in [IndexedDB](https://developer.mozilla.org/en-US/docs/Web/API/IndexedDB_API), a low-level API for web-based client-side storage.
  * > Note: Encryption on web is experimental through [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage#configure-web-version). It is important to enable the correct headers in order to ensure security of encryption on web.

## ⚙️ Configuration

Specify your preferred persistor on startup or use `Persistor.current()` to dynamically select the default persistence implementation for the current platform (`FilePersistor` on Android/iOS, `IndexedDBPersistor` on web).


```dart
void main() {
  Loon.configure(persistor: Persistor.current());
  // Loon.configure(persistor: FilePersistor());
  // Loon.configure(persistor: SqlitePersistor());

  Loon.hydrate().then(() {
    print('Hydration complete');
  });

  runApp(const MyApp());
}
```

No persisted data is available on startup until it is manually requested by calling `hydrate`.

The call to `hydrate` returns a `Future` that resolves when the data has been hydrated from the persistence layer. By default, calling `hydrate()` will hydrate all persisted data. If only certain data should be hydrated, then it can be called with a list of documents and collections to hydrate. All subcollections of the specified paths are also hydrated.

```dart
await Loon.hydrate([
  Loon.doc('current_user_id'),
  Loon.collection('users'),
]);
```

## ⚙️ Dynamic options

Persistence options can be specified both globally as well as on a per-collection basis.

```dart
// main.dart
void main() {
  // Globally enable encryption.
  Loon.configure(persistor: FilePersistor(settings: PersistorSettings(encrypted: true));

  Loon.hydrate().then(() {
    print('Hydration complete');
  });
}

// models/user.dart
class UserModel {
  final String name;
  final int age;

  UserModel({
    required this.name,
    required this.age,
  });

  static Collection<UserModel> get store {
    return Loon.collection(
      'users',
      fromJson: UserModel.fromJson,
      toJson: (user) => user.toJson(),
      // Disable encryption specifically for this collection and its subcollections.
      settings: PersistorSettings(encrypted: false),
    )
  }
}
```

In this example, file encryption is enabled globally for all collections, but disabled
specifically for the users collection and its subcollections in the store.

By default all data in a single  `__store__.json` persistence file.

```
loon >
  __store__.json
```

If data needs to be persisted differently, either by merging data across collections into a single store or by breaking down a collection
into multiple stores, then a custom persistence key can be specified on the collection:

```dart
class UserModel {
  final String name;
  final int age;

  UserModel({
    required this.name,
    required this.age,
  });

  static Collection<UserModel> get store {
    return Loon.collection(
      'users',
      fromJson: UserModel.fromJson,
      toJson: (user) => user.toJson(),
      settings: PersistorSettings(
        key: Persistor.key('users'),
      ),
    )
  }
}
```

In the updated example, data from the users collection is now stored in a separate file store:

```dart
loon >
  __store__.json
  users.json
```

If documents need to be stored in different files based on their data, then a `Persistor.keyBuilder` can be used:

```dart
class UserModel {
  final String name;
  final int age;

  UserModel({
    required this.name,
    required this.age,
  });

  static Collection<UserModel> get store {
    return Loon.collection(
      'users',
      fromJson: UserModel.fromJson,
      toJson: (user) => user.toJson(),
      settings: PersistorSettings(
        key: Persistor.keyBuilder((snap) {
          if (snap.data.age >= 18) {
            return 'adult_users';
          }
          return 'users';
        }),
      ),
    )
  }
}
```

```dart
loon >
  __store__.json
  users.json
  adult_users.json
```

Now instead of storing all users in the `users.json` file, they will be distributed across multiple files based on the user's age. The key is recalculated
whenever a document's data changes and if its associated key is updated, then the document is moved from its previous file to its updated location.

## 🎨 Custom persistence

If you would prefer to persist data using an alternative implementation than the default persistors, you can implement the persistence interface:

```dart
import 'package:loon/loon.dart';

class MyPersistor extends Persistor {
  /// Initialization function called when the persistor is instantiated to execute and setup work.
  Future<void> init();

  /// Persist function called with the bath of documents that have changed (including been deleted) within the last throttle window
  /// specified by the [Persistor.persistenceThrottle] duration.
  Future<void> persist(Set<Document> docs);

  /// Hydration function called to read data from persistence. If no references are specified,
  /// then it hydrates all persisted data. if refs are specified, it hydrates only the data at
  /// and under those paths.
  Future<Json> hydrate([Set<StoreReference>? refs]);

  /// Clear function used to clear all documents under the given store paths.
  Future<void> clear(Set<StoreReference> refs);

  /// Clears all documents and removes all persisted data.
  Future<void> clearAll();
}
```

## Extensions

* [Firestore](https://pub.dev/packages/cloud_firestore): The [loon_extension_firestore](https://github.com/danReynolds/loon_extension_firestore) package is used to sync documents fetched from Firestore into Loon.
* [Haste](https://github.com/danReynolds/haste/blob/main/packages/haste_loon/README.md) Provides a set of Flutter hooks for accessing `Loon` documents and queries in Flutter widgets.

## Documents

* [Architecture](./docs/architecture.md): An architecture doc that breaks down the inner workings of the library.
* [Debugging](./docs/debug.md): A debugging doc that calls out any known issues or troubleshooting suggestions across different platforms.

## Happy coding

That's all for now! Want a feature? Found a bug? Create an issue!
