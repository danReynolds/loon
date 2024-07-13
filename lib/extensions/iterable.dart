part of loon;

extension IterableExtensions<T> on Iterable<T> {
  T? get tryLast {
    if (isEmpty) {
      return null;
    }
    return last;
  }
}
