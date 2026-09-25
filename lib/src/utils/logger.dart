part of '../loon.dart';

class Logger {
  final String _name;
  bool? _enabled;
  final Logger? parent;
  final void Function(String message)? output;

  Logger(
    this._name, {
    this.parent,
    this.output,
    bool? enabled,
  }) : _enabled = enabled;

  Logger child(
    String name, {
    void Function(String message)? output,
  }) {
    return Logger(name, output: output ?? this.output, parent: this);
  }

  String get name {
    if (parent != null) {
      return "${parent!.name} -> $_name";
    }
    return _name;
  }

  bool get enabled {
    return _enabled ?? parent?.enabled ?? kDebugMode;
  }

  set enabled(bool enabled) {
    _enabled = enabled;
  }

  void log(String message) {
    if (!enabled) {
      return;
    }

    final formattedMessage = '$name -> $message';

    if (output != null) {
      output!(formattedMessage);
    } else if (kDebugMode) {
      print(formattedMessage);
    }
  }

  Future<T> measure<T>(
    String label,
    Future<T> Function() task,
  ) async {
    if (!kDebugMode) {
      return task();
    }

    final stopwatch = Stopwatch()..start();

    try {
      log('$label started.');

      final result = await task();

      stopwatch.stop();

      log('$label completed in ${stopwatch.elapsedMilliseconds}ms.');

      return result;
    } catch (e) {
      stopwatch.stop();

      log('$label failed in ${stopwatch.elapsedMilliseconds}ms.');

      rethrow;
    }
  }
}
