part of loon;

typedef Json = Map<String, dynamic>;

typedef FilterFn<T> = bool Function(DocumentSnapshot<T> snap);
typedef SortFn<T> = int Function(DocumentSnapshot<T> a, DocumentSnapshot<T> b);

typedef ModifyFn<T> = T Function(DocumentSnapshot<T>? snap);

typedef FromJson<T> = T Function(Json json);

typedef ToJson<T> = Json Function(T model);
