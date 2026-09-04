import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loon/persistor/lock.dart';

import '../../utils.dart';

const _workDuration = Duration(milliseconds: 10);
const _burstWorkDuration = Duration(milliseconds: 5);

void main() {
  group('Lock', () {
    test(
      'Serializes a single waiter behind the holder',
      () {
        fakeAsync((async) {
          final lock = Lock();
          final order = <String>[];
          var aComplete = false;
          var bComplete = false;

          lock.run(() async {
            order.add('A-start');
            await Future.delayed(_workDuration);
            order.add('A-end');
          }).then((_) => aComplete = true);

          async.flushMicrotasks();

          lock.run(() async {
            order.add('B-start');
            await Future.delayed(_workDuration);
            order.add('B-end');
          }).then((_) => bComplete = true);

          async.flushMicrotasks();
          expect(order, ['A-start']);
          expect(aComplete, false);
          expect(bComplete, false);

          elapseAndFlush(async, _workDuration);
          expect(order, ['A-start', 'A-end', 'B-start']);
          expect(aComplete, true);
          expect(bComplete, false);

          elapseAndFlush(async, _workDuration);
          expect(order, ['A-start', 'A-end', 'B-start', 'B-end']);
          expect(bComplete, true);
        });
      },
    );

    test(
      'Serializes multiple waiters that all queue on the same holder',
      () {
        fakeAsync((async) {
          final lock = Lock();
          var inFlight = 0;
          var maxInFlight = 0;
          var completed = 0;

          void work() {
            lock.run(() async {
              inFlight++;
              if (inFlight > maxInFlight) maxInFlight = inFlight;
              await Future.delayed(_workDuration);
              inFlight--;
            }).then((_) => completed++);
          }

          work();
          async.flushMicrotasks();
          work();
          work();
          async.flushMicrotasks();

          expect(maxInFlight, 1);
          expect(completed, 0);

          elapseAndFlush(async, _workDuration);
          expect(maxInFlight, 1);
          expect(completed, 1);

          elapseAndFlush(async, _workDuration);
          expect(maxInFlight, 1);
          expect(completed, 2);

          elapseAndFlush(async, _workDuration);
          expect(maxInFlight, 1);
          expect(completed, 3);
        });
      },
    );

    test(
      'Serializes a burst of concurrent acquires',
      () {
        fakeAsync((async) {
          final lock = Lock();
          var inFlight = 0;
          var maxInFlight = 0;
          var completed = 0;

          void work() {
            lock.run(() async {
              inFlight++;
              if (inFlight > maxInFlight) maxInFlight = inFlight;
              await Future.delayed(_burstWorkDuration);
              inFlight--;
              completed++;
            });
          }

          for (var i = 0; i < 10; i++) {
            work();
          }

          async.flushMicrotasks();
          expect(maxInFlight, 1);

          for (var i = 0; i < 10; i++) {
            elapseAndFlush(async, _burstWorkDuration);
            expect(maxInFlight, 1);
          }

          expect(completed, 10);
        });
      },
    );

    test(
      'Releases the lock even when the callback throws',
      () async {
        final lock = Lock();

        await expectLater(
          lock.run(() async {
            throw StateError('boom');
          }),
          throwsA(isA<StateError>()),
        );

        var ran = false;
        await lock.run(() async {
          ran = true;
        }).timeout(const Duration(seconds: 1));

        expect(ran, true);
      },
    );

    test(
      'Returns the callback result through run',
      () async {
        final lock = Lock();
        final result = await lock.run(() async => 42);
        expect(result, 42);
      },
    );
  });
}
