import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';
import 'package:loon/persistor/worker/persistor_worker_messenger.dart';

void main() {
  group('PersistorWorkerMessenger.failAll', () {
    // Regression: a crashed or exited worker isolate previously left every
    // pending request hanging forever because no one completed the completers
    // in the index. failAll must error every pending awaiter and clear the
    // index so the messenger doesn't leak completers across reconnects.

    PersistorWorkerMessenger newMessenger() {
      return PersistorWorkerMessenger(
        logger: Logger('test'),
        onSync: null,
      );
    }

    test('Errors every pending completer with the given error', () async {
      final m = newMessenger();
      final a = Completer<void>();
      final b = Completer<void>();
      m.index['a'] = a;
      m.index['b'] = b;

      m.failAll(Exception('worker crashed'));

      await expectLater(a.future, throwsA(isA<Exception>()));
      await expectLater(b.future, throwsA(isA<Exception>()));
    });

    test('Clears the index so no completers leak after the worker dies',
        () async {
      final m = newMessenger();
      final a = Completer<void>();
      final b = Completer<void>();
      // Attach error handlers so completeError doesn't bubble as an unhandled
      // exception when the test only inspects the index.
      a.future.catchError((_) {});
      b.future.catchError((_) {});
      m.index['a'] = a;
      m.index['b'] = b;

      m.failAll(Exception('boom'));

      expect(m.index, isEmpty);
    });

    test('Is a no-op when there are no pending requests', () {
      final m = newMessenger();
      expect(() => m.failAll(Exception('boom')), returnsNormally);
    });

    test('Skips completers that have already completed', () async {
      final m = newMessenger();
      final c = Completer<void>();
      c.complete();
      m.index['a'] = c;

      // Must not throw "Future already completed".
      expect(() => m.failAll(Exception('boom')), returnsNormally);
      await expectLater(c.future, completes);
    });

    test('Rejects sends issued after the worker has died', () async {
      // Without this, post-crash callers would create new completers, send to
      // a dead isolate (silently dropped), and hang forever waiting for a
      // response that never comes.
      final m = newMessenger();
      m.failAll(Exception('worker crashed'));

      await expectLater(m.clearAll(), throwsA(isA<Exception>()));
      expect(m.index, isEmpty);
    });
  });
}
