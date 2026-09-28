part of '../loon.dart';

// Reference checks are called only inside assertions.
bool _isValidReferenceSegment(String value) =>
    value.isNotEmpty && !value.contains('__') && !value.endsWith('_');

bool _isValidCollectionPath(String path) {
  final segments = path.split('__');
  return segments.length.isOdd && segments.every(_isValidReferenceSegment);
}

bool _isValidDocumentPath(String path) {
  final segments = path.split('__');
  return segments.length.isEven && segments.every(_isValidReferenceSegment);
}

bool _isSerializable(dynamic data) {
  if (data == null || data is num || data is String || data is bool) {
    return true;
  }

  if (data is Map) {
    try {
      jsonEncode(data);
      return true;
    } catch (e) {
      return false;
    }
  }

  return false;
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
        if (fromJson == null && T != Json) {
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
