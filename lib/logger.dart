import 'package:flutter/foundation.dart';

void printDebug(
  String message, {
  String? label = 'Loon',
}) {
  if (kDebugMode) {
    print('$label: $message');
  }
}
