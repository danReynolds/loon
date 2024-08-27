part of loon;

extension LoonIterableExtensions<T> on Iterable<T> {
  T? get tryLast {
    if (isEmpty) {
      return null;
    }
    return last;
  }

  Iterable<T> get distinct {
    if (isEmpty) {
      return this;
    }

    final Set<T> items = {};
    return where((item) {
      if (items.contains(item)) {
        return false;
      }
      items.add(item);
      return true;
    });
  }
}
