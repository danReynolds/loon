part of './loon.dart';

/// A mixin that provides an observable interface for the access and streaming of data broadcasted from the store.
mixin BroadcastObserver<T, S> {
  late final StreamController<T> _controller;
  late final StreamController<S> _changeController;

  /// Whether the [Observable] can have more than one observable subscription. A single-subscription
  /// observable will allow one listener and release its resources automatically when its listener cancels its subscription.
  /// A multicast observable must have its resources released manually by calling [dispose].
  /// The term *multicast* is used to refer to a a multi-subscription observable since it is common observable terminology and
  /// the term broadcast is to mean something different in the library compared to its usage in the underlying Dart [Stream] implementation.
  late final bool multicast;

  /// The latest value emitted on the observer's stream controller. This value can be different
  /// from the *current* value of the observer, which may not have been broadcast on its stream yet
  /// and is cached in the [BroadcastManager].
  late T _controllerValue;

  /// The unique ID of the observer instance.
  late String _observerId;

  /// The path being observed in the store.
  String get path;

  /// The dependencies of the observer in the store.
  final _deps = PathRefStore();

  void _init(
    T initialValue, {
    required bool multicast,
  }) {
    this.multicast = multicast;

    if (multicast) {
      _controller = StreamController<T>.broadcast();
      _changeController = StreamController<S>.broadcast();
    } else {
      _controller = StreamController<T>(onCancel: dispose);
      _changeController = StreamController<S>(onCancel: dispose);
    }

    _controllerValue = initialValue;
    _controller.add(initialValue);

    _observerId = "${path}__${generateId()}";

    Loon._instance.broadcastManager.addObserver(this, initialValue);
  }

  void dispose() {
    _controller.close();
    _changeController.close();
    Loon._instance.broadcastManager.removeObserver(this);
  }

  T add(T updatedValue) {
    Loon._instance.broadcastManager.observerValueStore
        .write(_observerId, updatedValue);
    _controller.add(updatedValue);
    return _controllerValue = updatedValue;
  }

  Stream<T> stream() {
    return _controller.stream;
  }

  Stream<S> streamChanges() {
    return _changeController.stream;
  }

  bool get isDirty;

  T? get _value {
    return Loon._instance.broadcastManager.observerValueStore.get(_observerId);
  }

  set _value(T? value) {
    Loon._instance.broadcastManager.observerValueStore
        .write(_observerId, value);
  }

  /// Updates the observer's dependency graph given the change in its previous and updated set of dependencies.
  void _updateDeps(Set<Document>? prevDeps, Set<Document>? deps) {
    if (deps != null && prevDeps != null) {
      final addedDeps = deps.difference(prevDeps);
      final removedDeps = prevDeps.difference(deps);

      for (final dep in addedDeps) {
        _deps.inc(dep.path);
      }
      for (final dep in removedDeps) {
        _deps.dec(dep.path);
      }
    } else if (deps != null) {
      for (final dep in deps) {
        _deps.inc(dep.path);
      }
    } else if (prevDeps != null) {
      for (final dep in prevDeps) {
        _deps.dec(dep.path);
      }
    }
  }

  void _onBroadcast();
}
