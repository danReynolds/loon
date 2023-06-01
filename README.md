# Loon

<img src="https://github.com/danReynolds/loon/assets/2192930/8d03dc8f-9d43-4b7e-951d-5e54ec857897" width="300" height="300">
<br />
<br />

Loon is a reactive, key/value data store for Dart & Flutter.

## Features

* Synchronous reading, writing and querying of documents.
* Streaming of changes to documents and queries.
* Built-in file persistence with options for per-collection encryption and sharding.

## ➕ Creating documents

Loon is based around collections of documents.

```dart
import 'package:loon/loon.dart';

Loon.collection('reviews').doc('The Book of Boba Fett').create({
  'rating': 3/10,
  'review': "A largely disappointing series that played it too safe and didn't live up to fan expectations for the character.",
});
```

Documents are stored under collections in a map structure that allows for synchronous reading/writing. To get type safety, you can define your own classes to represent collections and implement a serializer:

```dart
import 'package:loon/loon.dart';
import './models/reviews.dart';

Loon.collection<ReviewModel>(
  'reviews',
  fromJson: (Json json) => ReviewModel.fromJson(json),
  toJson: (review) => review.toJson(),
).doc('Obi-Wan Kenobi').create(
  ReviewModel(
    rating: 6/10,
    review: "The show had its moments, but they really should have de-aged Anakin.",
  )
);
```

To get reusable type safety and serialization, it can be helpful to define a collection index on your model:

```dart
import 'package:loon/loon.dart';

class ReviewModel {
  final double rating;
  final String review;

  ReviewModel({required this.rating, required this.review});

  static Collection<ReviewModel> get store {
    return Loon.collection<ReviewModel>(
      'reviews',
      fromJson: (Json json) => ReviewModel.fromJson(json),
      toJson: (review) => review.toJson(),
    )
  }
}
```

You can then read and write documents in your collection using the index:

```dart
import './models/reviews.dart';

ReviewModel.store.doc('Andor').create(
  ReviewModel(
    rating: 8/10,
    review: "Definitely a quality jump from Boba and Obi-Wan. Great writing, expect less action and more intrigue.",
  )
);
```

## 📚 Reading documents

```dart
import './models/reviews.dart';

final snap = ReviewModel.store.doc('The Book of Boba Fett').get();

if (snap != null && snap.data.rating > 8/10) {
  print('Great show') // Unreachable
}
```

Reading documents returns a `DocumentSnapshot?` which exposes your document's data and ID:

```dart
print(snap.id) // Book of Boba Fett
print(snap.data) // ReviewModel(...)
```

To watch for changes to a document, you can read it as a stream:

```dart
import './models/reviews.dart';

ReviewModel.store.doc('Obi-Wan').stream().listen((snap) {});
```

You can then use Flutter's built-in `StreamBuilder` or the provided `DocumentStreamBuilder` widget to then stream updates to documents data in your UI:

```dart
import './models/reviews.dart';
import 'package:loon/loon.dart';

class MyWidget extends StatelessWidget {
  @override
  build(context) {
    return DocumentStreamBuilder<ReviewModel>(
      doc: ReviewModel.store.doc('Andor'),
      builder: (context, snap) {
        final rating = snap.data.rating;

        return Text('A pretty good show, just look at the rating: ${rating}');
      }
    )
  }
}
```

You can read multiple documents using queries:

```dart
import './models/reviews.dart';

final snapshots = ReviewModel.store.where((snap) => snap.data.rating >= 5/10).get();
for (final snap in snapshots) {
  print(snap.id);
  // Obi-Wan
  // Andor
}
```

You can stream queries just like documents, with an option to use the `QueryStreamBuilder`:

```dart
import 'package:loon/loon.dart';
import './models/reviews.dart';

class MyWidget extends StatelessWidget {
  @override
  build(context) {
    return QueryStreamBuilder<ReviewModel>(
      query: ReviewModel.store.where((snap) => snap.data.rating >= 5/10),
      builder: (context, snapshots) {
        return ListView.builder(
          itemCount: snapshots.length,
          builder: (context, snap) {
            return Text('I gave ${snap.id} a ${snap.data.rating}.');
          }
        )
      }
    )
  }
}
```

## ✏️ Updating documents

Assuming our model has a `copyWith` function, we can then perform updates to documents like this:

```dart
import './models/reviews.dart';

final doc = ReviewModel.doc('The Book of Boba Fett');
final review = doc.get();

doc.update(
  review.copyWith(
    rating: 4/10,
    review: "If I take the Mando episodes out it actually feels even lower.",
  ),
);
```

If we don't want to read the document first, we can use the `modify` API:

```dart
import './models/reviews.dart';

ReviewModel.doc('The Book of Boba Fett').modify((review) {
  return review.copyWith(
    rating: 3/10,
    review: "They really did my boy dirty",
  );
})
```

## ❌ Deleting documents

Short and sweet, just call delete:

```dart
import './models/reviews.dart';

ReviewModel.doc('The Book of Boba Fett').delete(); // Good riddance.
```

## Persisting Data

The library comes with two persistence options out of the box:

`FilePersistor` and `EncryptedFilePersistor`.

You can specify which one you want to use by default for all collections like this:

```dart
import 'package:loon/loon.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  Loon.configure(persistor: FilePersistor());

  runApp(const MyApp());
}
```

When changes occur to documents in the app, they are batched and written to a file per collection. In the case of the `reviews` collection, it would be: `loon_reviews.json`.

You can specify the frequency that batch updates should be written:

```dart
import 'package:loon/loon.dart';

FilePersistor(
  persistenceThrottle: Duration(milliseconds: 200),
)
```

as well as specify custom options per collection, like sharding documents:

```dart
import 'package:loon/loon.dart';

class ReviewModel {
  final double rating;
  final String review;

  ReviewModel({required this.rating, required this.review});

  static Collection<ReviewModel> get store {
    return Loon.collection<ReviewModel>(
      'reviews',
      persistorSettings: FilePersistorSettings(
        shardFn: (doc) {
          final snap = doc.get();
          final rating = snap.data.rating ?? 0;

          return rating >= 6/10 ? 'good' : 'bad';
        },
      ),
      fromJson: (Json json) => ReviewModel.fromJson(json),
      toJson: (review) => review.toJson(),
    )
  }
}
```

In this example, the documents in our reviews collection would be spread across multiple files:

* `reviews_good.json`:
  * Obi-Wan
  * Andor
* `reviews_bad.json`:
  * The Book of Boba Fett

If some of your collections contain sensitive data, you can choose to encrypt them by using the `EncryptedFilePersistor` instead (no web support yet), either globally:

```dart
import 'package:loon/loon.dart';

import 'package:loon/loon.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  Loon.configure(persistor: EncryptedFilePersistor());

  runApp(const MyApp());
}
```

or on a per-collection basis:

```dart
import 'package:loon/loon.dart';

class ReviewModel {
  final double rating;
  final String review;

  ReviewModel({required this.rating, required this.review});

  static Collection<ReviewModel> get store {
    return Loon.collection<ReviewModel>(
      'reviews',
      persistorSettings: EncryptedFilePersistorSettings(
        isEncrypted: true,
      ),
      fromJson: (Json json) => ReviewModel.fromJson(json),
      toJson: (review) => review.toJson(),
    )
  }
}
```

Encrypted files are stored similarly to default file persistence, in this case it would be: `loon_reviews.encrypted.json`.

## Custom persistence

If you don't want to use the provided persistence options, it's pretty straightforward to use your own, just implement the persistence interface:

```dart
import 'package:loon/loon.dart';

typedef DocumentDataStore = Map<String, Json>;
typedef CollectionDataStore = Map<String, DocumentDataStore>;

class MyPersistor extends Persistor {
  Future<void> persist(List<BroadcastDocument> docs);

  Future<CollectionDataStore> hydrate();

  Future<void> clear(String collection);
}
```

The base `Persistor` class implements batching and throttling, so you can just choose your storage mechanism and format.

## Loon time coming

I've been wanting to play around with building a data store library for a while, incorporating some reflections from working with web libraries like `Redux`, `ApolloClient` and Flutter libraries like `cloud_firestore` (the collection/document pattern most notably).

The library is really new and I'm still thinking about the streaming and persistence models so feel free to give feedback.

Happy coding!
