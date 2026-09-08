part of './loon.dart';

/// A mixin that provides an observable interface for the access and streaming of data broadcasted from the store.
mixin BroadcastObserver<T, S> {
  StreamController<T>? _controller;
  StreamController<S>? _changeController;

  /// Whether the observer has been disposed. A disposed observer releases its controllers and
  /// last value, so that anything still referencing it retains nothing of its observer state.
  bool _disposed = false;

  /// Whether the [Observable] can have more than one observable subscription. A single-subscription
  /// observable will allow one listener and release its resources automatically when its listener cancels its subscription.
  /// A multicast observable must have its resources released manually by calling [dispose].
  /// The term *multicast* is used to refer to a a multi-subscription observable since it is common observable terminology and
  /// the term broadcast is to mean something different in the library compared to its usage in the underlying Dart [Stream] implementation.
  late final bool multicast;

  /// The latest value emitted on the observer's stream controller. This value can be different
  /// from the *current* value of the observer, which may not have been broadcast on its stream yet
  /// and is cached in the [BroadcastManager].
  T? _controllerValue;

  /// The unique ID of the observer instance.
  late String _observerId;

  /// The path being observed in the store.
  String get path;

  void _init(
    T initialValue, {
    required bool multicast,
  }) {
    this.multicast = multicast;

    final StreamController<T> controller;
    final StreamController<S> changeController;
    if (multicast) {
      controller = StreamController<T>.broadcast();
      changeController = StreamController<S>.broadcast();
    } else {
      controller = StreamController<T>(onCancel: dispose);
      changeController = StreamController<S>(onCancel: dispose);
    }
    _controller = controller;
    _changeController = changeController;

    _controllerValue = initialValue;
    controller.add(initialValue);

    _observerId = "${path}__${generateFastId()}";

    Loon._instance.broadcastManager.addObserver(this, initialValue);
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;

    _controller?.close();
    _changeController?.close();
    // The controllers and last value are released so that a disposed observer that is still
    // referenced elsewhere, such as through a snapshot written through it, retains nothing.
    _controller = null;
    _changeController = null;
    _controllerValue = null;

    Loon._instance.broadcastManager.removeObserver(this);
  }

  T add(T updatedValue) {
    Loon._instance.broadcastManager.observerValueStore
        .write(_observerId, updatedValue);
    _controller?.add(updatedValue);
    _controllerValue = updatedValue;
    return updatedValue;
  }

  /// The observer's stream of values. A disposed observer's stream is empty.
  Stream<T> stream() {
    return _controller?.stream ?? Stream<T>.empty();
  }

  /// The observer's stream of changes. A disposed observer's stream is empty.
  Stream<S> streamChanges() {
    return _changeController?.stream ?? Stream<S>.empty();
  }

  bool get isDirty;

  T? get _value {
    return Loon._instance.broadcastManager.observerValueStore.get(_observerId);
  }

  set _value(T? value) {
    Loon._instance.broadcastManager.observerValueStore
        .write(_observerId, value);
  }

  void _onBroadcast();
}
