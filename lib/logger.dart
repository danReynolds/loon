import 'package:flutter/foundation.dart';
import 'package:loon/loon.dart';

class Logger {
  final String name;
  final void Function(String message)? output;

  Logger(
    this.name, {
    this.output,
  });

  void log(String message) {
    if (Loon.isLoggingEnabled) {
      // ignore: avoid_print
      print('Loon $name: $message');
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

      (output ?? log)
          .call('$label completed in ${stopwatch.elapsedMilliseconds}ms');

      return result;
    } catch (e) {
      stopwatch.stop();

      log('$label failed in ${stopwatch.elapsedMilliseconds}ms');

      rethrow;
    }
  }
}
