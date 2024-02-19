# Loon

<img src="https://github.com/danReynolds/loon/assets/2192930/8d03dc8f-9d43-4b7e-951d-5e54ec857897" width="300" height="300">
<br />
<br />

Loon is a reactive collection data store for Flutter.

## Features

* Synchronous reading, writing and querying of documents.
* Streaming of changes to documents and queries.
* Out of the box persistence and encryption.

You can get started by looking at the [example](./example/lib/main.dart).

## ➕ Creating documents

Loon is based around collections of documents.

```dart
import 'package:loon/loon.dart';

Loon.collection('birds').doc('loon').create({
  'name': 'Loon',
  'description': 'The loon is an aquatic bird native to North America and parts of Northern Eurasia.',
});
```

Documents are stored under collections in a map structure. They can contain any type of data, like a `Map` or a typed data model:

```dart
import 'package:loon/loon.dart';
import './models/reviews.dart';

Loon.collection<BirdModel>(
  'birds',
  fromJson: BirdModel.fromJson,
  toJson: (user) => user.toJson(),
).doc('loon').create(
  BirdModel(
    name: 'Loon',
    description: 'The loon is known for its distinctive black-and-white plumage, haunting calls, and remarkable diving ability.',
    family: 'Gaviidae',
  )
);
```

If persistence is enabled, then a typed data model will need a `fromJson/toJson` serialization pair. In order to avoid having to specify types or serializers whenever a collection is accessed, it can be helpful to store the collection in a variable or as an index on a data model:

```dart
import 'package:loon/loon.dart';

class BirdModel {
  final String name;
  final String description;
  final String species;

  BirdModel({
    required this.name,
    required this.description,
    required this.species,
  });

  static Collection<BirdModel> get store {
    return Loon.collection<BirdModel>(
      'birds',
      fromJson: BirdModel.fromJson,
      toJson: (bird) => bird.toJson(),
    )
  }
}
```

Documents can then be read/written using the index:

```dart
import './models/reviews.dart';

BirdModel.store.doc('cormorant').create(
  BirdModel(
    name: 'Cormorant',
    description: 'Cormorants are generally darker than loons, with an almost black plumage, and have a more hook-tipped beak',
    family: 'Phalacrocoracidae',
  ),
);
```

## 📚 Reading documents

```dart
import './models/birds.dart';

final snap = BirdModel.store.doc('loon').get();

if (snap != null && snap.id == 'loon') {
  print('Loons are excellent swimmers, using their feet to propel themselves above and under water.');
}
```

Reading a document returns a `DocumentSnapshot?` which exposes your document's data and ID:

```dart
print(snap.id) // loon
print(snap.data) // BirdModel(...)
```

To watch for changes to a document, you can read it as a stream:

```dart
import './models/birds.dart';

BirdModel.store.doc('loon').stream().listen((snap) {});
```

You can then use Flutter's built-in `StreamBuilder` or the library's `DocumentStreamBuilder` widget to access data from widgets:

```dart
import './models/birds.dart';
import 'package:loon/loon.dart';

class MyWidget extends StatelessWidget {
  @override
  build(context) {
    return DocumentStreamBuilder(
      doc: BirdModel.store.doc('loon'),
      builder: (context, snap) {
        final bird = snap?.data;

        if (bird == null) {
          return Text('Missing bird');
        }
        return Text(
          '''
          The common loon is the provincial bird of Ontario and is depicted on the Canadian one-dollar coin,
          which has come to be known affectionately as the "loonie".
          '''
        );
      }
    )
  }
}
```

## Subcollections

Documents support nested subcollections. Documents in subcollections are grouped under the parent document and are uniquely identified by their collection and
document ID.

```dart
final snaps = BirdModel.store.doc('loon').subcollection('prey').get();

for (final snap in snaps) {
  print("${snap.id}: ${snap.collection}");
  // crayfish: birds_loon_crayfish
  // frogs: birds_loon_frogs
  // snails: birds_loon_snails
}
```

## Queries

Documents can be read and filtered using queries:

```dart
import './models/birds.dart';

final snapshots = BirdModel.store.where((snap) => snap.data.family == 'Gaviidae').get();
for (final snap in snapshots) {
  print(snap.data.name);
  // Red-throated Loon
  // Pacific Loon
  // Common Loon
}
```

Queries can also be streamed, optionally using the `QueryStreamBuilder`:

```dart
import 'package:loon/loon.dart';
import './models/birds.dart';

class MyWidget extends StatelessWidget {
  @override
  build(context) {
    return QueryStreamBuilder(
      query: BirdModel.store.where((snap) => snap.data.family == 'Phalacrocoracidae'),
      builder: (context, snaps) {
        return ListView.builder(
          itemCount: snaps.length,
          builder: (context, snap) {
            return Text('Phalacrocoracidae is a family of approximately 40 species of aquatic birds including the ${snap.data.name}');
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
final doc = BirdModel.doc('loon');
final snap = doc.get();

doc.update(
  snap.data.copyWith(
    description: 'Loons are monogamous, a single female and male often together defend a territory and may breed together for a decade or more',
  ),
);
```

The reading and writing of a document can be combined using the `modify` API. If the document does not yet exist, then its snapshot is null.

```dart
BirdModel.doc('loon').modify((snap) {
  if (snap == null) {
    return null;
  }
  return snap.data.copyWith(
    description: 'Loons nest during the summer on freshwater lakes and/or large ponds.',
  );
});
```

## ❌ Deleting documents

Deleting a document removes it and all of its subcollections from the store.

```dart
import './models/birds.dart';

BirdModel.doc('cormorant').delete();
```

## Streaming changes

Documents and queries can be streamed for changes which provides the reason for their rebroadcast:

```dart
BirdModel.store.streamChanges().listen((changes) {
  for (final changeSnap in changes) {
     switch(changeSnap.type) {
      case BroadcastEventTypes.added:
        print('New document ${changeSnap.id} was added to the collection.');
        break;
      case BraodcastEventTypes.modified:
        print('The document ${changeSnap.id} was modified from ${changeSnap.prevData} to ${changeSnap.data}');
        break;
      case BraodcastEventTypes.removed:
        print('${changeSnap.id} was removed from the collection.');
        break;
      case BraodcastEventTypes.hydrated:
        print('${changeSnap.id} was hydrated from the persisted data');
        break;
    }
  }
});
```

## Data Dependencies

Data relationships in the store can be established using the data dependencies builder.

```dart
final families = Loon.collection('families');

final birds = Loon.collection<BirdModel>(
  'birds',
  dependenciesBuilder: (snap) {
    return {
      famililes.doc(snap.data.family),
    };
  },
);
```

In this example, whenever a bird's given family is updated, the bird will be rebroadcast as well to any of its listeners.

## Data Persistence

A default file-based persistence option is available out of the box and can be configured on app start.

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  Loon.configure(persistor: FilePersistor());

  Loon.hydrate().then(() {
    print('Hydration complete');
  });

  runApp(const MyApp());
}
```

The call to `hydrate` returns a `Future` that resolves when the data has been hydrated from the persistence layer. It can be awaited to ensure that
data is available before proceeding, otherwise hydrated data will be merged on top of any data already in the store.

## Persistence options

Persistence options can be specified globally or on a per-collection basis.

```dart
// main.dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  Loon.configure(persistor: FilePersistor(encryptionEnabled: true));

  Loon.hydrate().then(() {
    print('Hydration complete');
  });
}

// models/birds.dart
class BirdModel {
  final String name;
  final String description;
  final String species;

  BirdModel({
    required this.name,
    required this.description,
    required this.species,
  });

  static Collection<BirdModel> get store {
    return Loon.collection<BirdModel>(
      'birds',
      fromJson: BirdModel.fromJson,
      toJson: (bird) => bird.toJson(),
      settings: FilePersistorSettings(
        encryptionEnabled: false,
      ),
    )
  }
}
```

In this example, file encryption is enabled globally for all collections, but disabled
specifically for the bird collection.

By default, file persistence stores data in files on a per collection basis. The above `birds` collection is stored as:

```
loon >
  birds.json
```

If data needs to be persisted differently, either by merging data across collections into a single file or by breaking down a collection
into multiple files, then a custom persistence key can be specified on the collection.

```dart
class BirdModel {
  final String name;
  final String description;
  final String species;

  BirdModel({
    required this.name,
    required this.description,
    required this.species,
  });

  static Collection<BirdModel> get store {
    return Loon.collection<BirdModel>(
      'birds',
      fromJson: BirdModel.fromJson,
      toJson: (bird) => bird.toJson(),
      settings: FilePersistorSettings(
        getPersistenceKey: (snap) {
          return 'birds_${snap.data.family};
        }
      ),
    )
  }
}
```

In the updated example, data from the collection is now broken down into multiple files based on the document data:

```dart
loon >
  birds_phalacrocoracidae.json
  birds_gaviidae.json
```

## Custom persistence

If you would prefer to persist data using an alternative implementation than the default `FilePersistor`, you just need to implement the persistence interface:

```dart
import 'package:loon/loon.dart';

class MyPersistor extends Persistor {
  Future<void> init();

  Future<void> persist(List<Document> docs);

  Future<SerializedCollectionStore> hydrate();

  Future<void> clear(String collection);

  Future<void> clearAll();
}
```

The base `Persistor` class implements batching and throttling, so you can just choose your storage mechanism and format.

## Loon time coming

I've been wanting to play around with building a data store library for a while, incorporating some reflections from working with web libraries like `Redux`, `ApolloClient` and Flutter libraries like `cloud_firestore` (the collection/document pattern most notably).

The library is really new and I'm still thinking about the streaming and persistence models so feel free to give feedback.

Happy coding!
