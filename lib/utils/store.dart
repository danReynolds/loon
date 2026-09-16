part of '../loon.dart';

/// Finds the final non-overlapping delimiter, matching String.split even when
/// underscore runs overlap. Only the parent and final segment are materialized.
(String, String) _splitReferencePath(String path) {
  const delimiter = _BaseValueStore.delimiter;
  var boundary = -1;
  var start = 0;
  while (true) {
    final next = path.indexOf(delimiter, start);
    if (next < 0) break;
    boundary = next;
    start = next + delimiter.length;
  }
  return boundary < 0
      ? ('', path)
      : (path.substring(0, boundary), path.substring(start));
}
