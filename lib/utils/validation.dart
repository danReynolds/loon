part of loon;

/// In debug mode, assert that the data being written for a document is serializable.
void _validateDataSerialization<T>({
  required Document<T> doc,
  required bool persistenceEnabled,
  required ToJson<T>? toJson,
  required T? data,
}) {
  if (!persistenceEnabled || data == null || !kDebugMode) {
    return;
  }

  if (toJson == null) {
    try {
      jsonEncode(data);
    } catch (e) {
      throw MissingSerializerException<T>(
        doc,
        data,
        MissingSerializerTypes.write,
      );
    }
  }
}

/// In debug mode, assert that the data being parsed for a document is serializable.
void _validateDataDeserialization<T>({
  required Document doc,
  required FromJson<T>? fromJson,
  required dynamic data,
}) {
  if (data == null || !kDebugMode) {
    return;
  }

  try {
    jsonEncode(data);
  } catch (e) {
    throw DocumentTypeMismatchException<T>(doc, data);
  }

  if (fromJson == null) {
    throw MissingSerializerException<T>(
      doc,
      data,
      MissingSerializerTypes.read,
    );
  }
}
