import 'package:flutter_test/flutter_test.dart';
import 'package:loon/persistor/lock.dart';

void main() {
  group('Lock', () {
    test(
      'Serializes a single waiter behind the holder',
      () async {
        final lock = Lock();
        final order = <String>[];

        final a = lock.run(() async {
          order.add('A-start');
          await Future.delayed(const Duration(milliseconds: 10));
          order.add('A-end');
        });

        // Give A time to acquire before B arrives.
        await Future.delayed(Duration.zero);

        final b = lock.run(() async {
          order.add('B-start');
          await Future.delayed(const Duration(milliseconds: 10));
          order.add('B-end');
        });

        await Future.wait([a, b]);

        expect(order, ['A-start', 'A-end', 'B-start', 'B-end']);
      },
    );

    test(
      'Serializes multiple waiters that all queue on the same holder',
      () async {
        // Regression: previously, multiple waiters all awaited the same
        // completer, woke together on release, and each installed their own
        // completer — letting all of them think they held the lock at once.
        final lock = Lock();
        int inFlight = 0;
        int maxInFlight = 0;

        Future<void> work() {
          return lock.run(() async {
            inFlight++;
            if (inFlight > maxInFlight) maxInFlight = inFlight;
            await Future.delayed(const Duration(milliseconds: 10));
            inFlight--;
          });
        }

        // A holds. B and C both queue on A's completer.
        final a = work();
        await Future.delayed(Duration.zero);
        final b = work();
        final c = work();

        await Future.wait([a, b, c]);

        expect(maxInFlight, 1);
      },
    );

    test(
      'Serializes a burst of concurrent acquires',
      () async {
        final lock = Lock();
        int inFlight = 0;
        int maxInFlight = 0;
        int completed = 0;

        Future<void> work() {
          return lock.run(() async {
            inFlight++;
            if (inFlight > maxInFlight) maxInFlight = inFlight;
            await Future.delayed(const Duration(milliseconds: 5));
            inFlight--;
            completed++;
          });
        }

        final futures = List.generate(10, (_) => work());
        await Future.wait(futures);

        expect(maxInFlight, 1);
        expect(completed, 10);
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

        // The next acquire must complete; if the lock leaked, this hangs.
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
