part of loon;

class Logger {
  final String name;
  final void Function(String message)? output;

  Logger(
    this.name, {
    this.output,
  });

  void log(String message) {
    final formattedMessage = '$name->$message';

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
