import 'dart:async';
import 'dart:math';

import 'package:example/models/user.dart';
import 'package:loon/loon.dart';

enum Operations {
  hydrate,
  persist,
  clear,
  clearAll,
}

class RandomOperationRunner {
  final _period = const Duration(milliseconds: 400);
  final _logger = Logger('RandomOperationRunner');
  Timer? _timer;

  void _runOperation() {
    final operationIndex = Random().nextInt(100);

    if (operationIndex >= 0 && operationIndex < 80) {
      final count = Random().nextInt(10000);
      _logger.log('Persist $count');

      for (int i = 0; i < count; i++) {
        final id = uuid.v4();
        UserModel.store.doc(id).create(UserModel(name: 'User $id'));
      }
    } else if (operationIndex >= 80 && operationIndex < 90) {
      _logger.log('Clear');
      UserModel.store.delete();
    } else if (operationIndex >= 90 && operationIndex < 95) {
      _logger.log('Clear all');
      Loon.clearAll();
    } else {
      _logger.log('Hydrate');
      Loon.hydrate();
    }
  }

  bool get isRunning {
    return _timer != null;
  }

  void run() {
    if (isRunning) {
      return;
    }

    _timer = Timer.periodic(_period, (_) => _runOperation());
  }

  void stop() {
    if (!isRunning) {
      return;
    }

    _timer?.cancel();
    _timer = null;
  }
}
