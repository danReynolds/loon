import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:loon/logger.dart';

Future<T> measureDuration<T>(
  String label,
  Future<T> Function() task, {
  Function(String text)? output,
}) async {
  if (!kDebugMode) {
    return task();
  }

  final stopwatch = Stopwatch()..start();

  try {
    final result = await task();

    stopwatch.stop();

    final text = '$label - completed in ${stopwatch.elapsedMilliseconds}ms';
    output?.call(text) ?? printDebug(text);

    return result;
  } catch (e) {
    stopwatch.stop();

    rethrow;
  }
}
