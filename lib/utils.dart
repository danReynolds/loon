part of loon;

void _validateDataSerialization<T>({
  required FromJson<T>? fromJson,
  required ToJson<T>? toJson,
  required T? data,
}) {
  if (data is! Json? && (fromJson == null || toJson == null)) {
    throw Exception('Missing fromJson/toJson serializer');
  }
}

void _validateTypeSerialization<T>({
  required FromJson<T>? fromJson,
  required ToJson<T>? toJson,
}) {
  if (T != Json && T != dynamic && (fromJson == null && toJson == null)) {
    throw Exception('Missing fromJson/toJson serializer');
  }
}
