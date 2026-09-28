part of '../loon.dart';

const _underscore = 0x5f;

/// Names and IDs occupy one segment of a `__`-delimited reference path, so they must be nonempty,
/// contain no `__` and not end with `_`. Checked in one pass over the code units, since documents
/// are constructed often.
void _validateReferenceSegment(String value, String argumentName) {
  final length = value.length;
  var valid = length > 0 && value.codeUnitAt(length - 1) != _underscore;
  for (var i = 1; valid && i < length; i++) {
    valid = value.codeUnitAt(i) != _underscore ||
        value.codeUnitAt(i - 1) != _underscore;
  }
  if (!valid) {
    throw ArgumentError.value(value, argumentName,
        'Must be nonempty, contain no "__", and not end with "_"');
  }
}

String _checkedSegment(String value, String argumentName) {
  _validateReferenceSegment(value, argumentName);
  return value;
}

String _checkedPath(String path, String argumentName,
    {required bool isDocument}) {
  _validateReferencePath(path, argumentName, isDocument: isDocument);
  return path;
}

/// Validates a complete reference path in one pass, without allocating its segments. Segments are
/// split at `__` from left to right without overlapping, as the stores split paths. Collection
/// paths have an odd number of segments; document paths have an even number.
void _validateReferencePath(String path, String argumentName,
    {required bool isDocument}) {
  void invalidSegment() => throw ArgumentError.value(path, argumentName,
      'Path segments must be nonempty and must not end with "_"');

  var segments = 1;
  var start = 0;
  for (var i = 0; i < path.length - 1; i++) {
    if (path.codeUnitAt(i) == _underscore &&
        path.codeUnitAt(i + 1) == _underscore) {
      if (i == start || path.codeUnitAt(i - 1) == _underscore) {
        invalidSegment();
      }
      segments++;
      start = i + 2;
      i++;
    }
  }
  if (start == path.length || path.codeUnitAt(path.length - 1) == _underscore) {
    invalidSegment();
  }

  if (segments.isEven != isDocument) {
    throw ArgumentError.value(
        path,
        argumentName,
        isDocument
            ? 'Must be a document path with an even number of segments'
            : 'Must be a collection path with an odd number of segments');
  }
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
