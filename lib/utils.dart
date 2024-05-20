part of loon;

void _validateDataSerialization<T>({
  required bool persistenceEnabled,
  required FromJson<T>? fromJson,
  required ToJson<T>? toJson,
  required T? data,
}) {
  if (persistenceEnabled &&
      data is! Json? &&
      (fromJson == null || toJson == null)) {
    throw Exception('Missing fromJson/toJson serializer');
  }
}

void _validateTypeSerialization<T>({
  required bool persistenceEnabled,
  required FromJson<T>? fromJson,
  required ToJson<T>? toJson,
}) {
  if (persistenceEnabled &&
      T != Json &&
      T != dynamic &&
      (fromJson == null && toJson == null)) {
    throw Exception('Missing fromJson/toJson serializer');
  }
}
