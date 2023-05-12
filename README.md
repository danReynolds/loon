# Loon

<img src="https://github.com/danReynolds/loon/assets/2192930/8d03dc8f-9d43-4b7e-951d-5e54ec857897" width="300" height="300">

Loon is a reactive, noSQL data store for Dart & Flutter.

## Features

* Synchronous reading, writing and querying of documents.
* Streaming of changes to documents and queries.
* Built-in file persistence with options for per-collection sharding and encryption.

## ➕ Creating documents

Loon is based around collections of documents.

```dart
import 'package:loon/loon.dart';

Loon.collection('shows').doc('Boba Fett').create({
  'rating': 3/10,
  'description': "A largely disappointing series that played it too safe and didn't live up to fan's expectations for the character",
});
```

Documents are stored under their collections in a map structure that makes reading, writing and querying for documents always synchronous. Type safety is simple:

```dart
import 'package:loon/loon.dart';
import './models/shows.dart';

Loon.collection<ShowModel>('shows').doc('Obi-Wan').create(
  ShowModel(
    rating: 5/10,
    description: "The Obi-Wan show had its moments, but some of the plot didn't seem to make sense and they really should have de-aged Anakin.",
  )
);
```

To stop having to pass generics around everywhere, you can define a collection-accessor on your models that makes 

## Reading documents

```dart
import 'package:loon/loon.dart';

Loon.collection('shows').doc('Boba Fett').create({
  'rating': 3/10,
  'description': "A largely disappointing series that played it too safe and didn't live up to fan's expectations for the character",
});
```