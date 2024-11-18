part of 'loon.dart';

typedef Json = Map<String, dynamic>;

typedef FilterFn<T> = bool Function(DocumentSnapshot<T> snap);
typedef SortFn<T> = int Function(DocumentSnapshot<T> a, DocumentSnapshot<T> b);

typedef ModifyFn<T> = T Function(DocumentSnapshot<T>? snap);

typedef FromJson<T> = T Function(Json json);

typedef ToJson<T> = Json Function(T model);

typedef Optional<T> = T?;

/// Returns a set of documents that the document associated with the given [DocumentSnapshot]
/// is dependent on.
typedef DependenciesBuilder<T> = Set<Document>? Function(
  DocumentSnapshot<T> snap,
);
