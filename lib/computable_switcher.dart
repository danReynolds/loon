part of 'loon.dart';

/// A [ComputableSwitcher] is a higher-order [Computable] that is necessary to support the
/// [Computable.switchMap] operator, which switches to emitting values from the most recent
/// inner computable whenever a new outer computable is created.
class ComputableSwitcher<T> with Computable<T> {
  final Computable<Computable<T>> computable;

  ComputableSwitcher(this.computable);

  @override
  get() {
    return computable.get().get();
  }

  @override
  ObservableSwitcher<T> observe({
    bool multicast = false,
  }) {
    return ObservableSwitcher(computable, multicast: multicast);
  }

  @override
  stream() {
    return observe().stream();
  }

  @override
  streamChanges() {
    return observe().streamChanges();
  }
}
