part of loon;

bool _isSerializable(dynamic data) {
  return data == null ||
      data is num ||
      data is String ||
      data is bool ||
      data is Json;
}

/// In debug mode, assert that the data being written for a document is serializable.
void _validateDataSerialization<T>({
  required Document<T> doc,
  required ToJson<T>? toJson,
  required T? data,
}) {
  if (kDebugMode && !_isSerializable(data) && toJson == null) {
    throw MissingSerializerException<T>(
      doc,
      data,
      MissingSerializerEvents.write,
    );
  }
}

/// In debug mode, assert that the data being parsed for a document is serializable.
void _validateDataDeserialization<T>({
  required Document doc,
  required FromJson<T>? fromJson,
  required dynamic data,
}) {
  if (kDebugMode) {
    if (_isSerializable(data)) {
      if (data is Json) {
        if (fromJson == null && T is! Json) {
          throw MissingSerializerException<T>(
            doc,
            data,
            MissingSerializerEvents.read,
          );
        }
      } else if (data is! T) {
        throw DocumentTypeMismatchException<T>(doc, data);
      }
    } else {
      throw DocumentTypeMismatchException<T>(doc, data);
    }
  }
}
