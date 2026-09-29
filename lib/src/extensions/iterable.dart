part of '../loon.dart';

extension LoonIterableExtensions<T> on Iterable<T> {
  T? get tryLast {
    if (isEmpty) {
      return null;
    }
    return last;
  }
}
