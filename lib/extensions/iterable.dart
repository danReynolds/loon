part of loon;

extension LoonIterableExtensions<T> on Iterable<T> {
  T? get tryLast {
    if (isEmpty) {
      return null;
    }
    return last;
  }
}
