part of '../loon.dart';

extension LoonNestedSetExtensions<T> on Set<Set<T>> {
  Set<T> flatten() {
    return expand((item) => item).toSet();
  }
}
