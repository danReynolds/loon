import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:loon/logger.dart';

Future<T> measureDuration<T>(String label, Future<T> Function() task) async {
  if (!kDebugMode) {
    return task();
  }

  final stopwatch = Stopwatch()..start();

  try {
    final result = await task();

    stopwatch.stop();
    printDebug('$label - completed in ${stopwatch.elapsedMilliseconds}ms');

    return result;
  } catch (e) {
    stopwatch.stop();

    rethrow;
  }
}
