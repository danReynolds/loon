part of loon;

void printDebug(
  String message, {
  String? label = 'Loon',
}) {
  if (Loon.isLoggingEnabled) {
    // ignore: avoid_print
    print('$label: $message');
  }
}

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

Map inspectNode(StoreNode node) {
  final Map<dynamic, dynamic> index = {
    "children":
        node.children?.values.fold<Map<StoreNode, dynamic>>({}, (acc, child) {
      acc[child] = inspectNode(child);
      return acc;
    }),
  };

  if (node is Document) {
    index['snap'] = node._snap;
  }

  return index;
}
