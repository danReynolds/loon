import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';

void main() {
  group('PathRefStore', () {
    group('inc', () {
      test('Correctly increments the ref count', () {
        final store = PathRefStore();

        store.inc('posts__1');

        expect(store.inspect(), {
          "__ref": 1,
          "posts": {
            "__ref": 1,
            "1": 1,
          }
        });

        store.inc('posts__1');
        store.inc('posts__1__comments__2');
        store.inc('posts__1__comments__2__reactions__1');
        store.inc('posts__2');

        expect(store.inspect(), {
          "__ref": 5,
          "posts": {
            "__ref": 5,
            "1": {
              "__ref": 4,
              "comments": {
                "__ref": 2,
                "2": {
                  "__ref": 2,
                  "reactions": {
                    "__ref": 1,
                    "1": 1,
                  }
                }
              },
            },
            "2": 1,
          },
        });
      });
    });

    group("dec", () {
      test('Correctly decrements the ref count', () {
        final store = PathRefStore();

        store.inc('posts__1');
        store.inc('posts__1');
        store.inc('posts__2');
        store.inc('posts__3');

        expect(store.inspect(), {
          "__ref": 4,
          "posts": {
            "__ref": 4,
            "1": 2,
            "2": 1,
            "3": 1,
          },
        });

        store.dec('posts__1');

        expect(store.inspect(), {
          "__ref": 3,
          "posts": {
            "__ref": 3,
            "1": 1,
            "2": 1,
            "3": 1,
          },
        });

        store.dec('posts__1');
        store.dec('posts__2');
        store.dec('posts__3');

        expect(store.inspect(), {});
      });

      test("Does not decrement deeper nodes", () {
        final store = PathRefStore();

        store.inc('posts__1');
        store.inc('posts__2');
        store.inc('posts__1__comments__2');

        expect(store.inspect(), {
          "__ref": 3,
          "posts": {
            "__ref": 3,
            "1": {
              "__ref": 2,
              "comments": {
                "__ref": 1,
                "2": 1,
              },
            },
            "2": 1,
          },
        });

        store.dec('posts__1');

        expect(store.inspect(), {
          "__ref": 2,
          "posts": {
            "__ref": 2,
            "1": {
              "__ref": 1,
              "comments": {
                "__ref": 1,
                "2": 1,
              },
            },
            "2": 1,
          },
        });
      });
    });

    group('has', () {
      test('Returns true for paths that exists in the store', () {
        final store = PathRefStore();

        store.inc('users__1__posts__1');

        expect(store.has('users__1'), true);
        expect(store.has('users__1__posts__1'), true);
        expect(store.has('users__2'), false);
        expect(store.has('users__1__posts__1__reactions__1'), false);
      });
    });

    group('dec on un-incremented paths', () {
      // Regression: previously `dec` reached `node[_refKey]--` even when the
      // path was never inc'd through that node, crashing with
      // NoSuchMethodError: '-' called on null.

      test('Single-segment dec on an empty store is a no-op', () {
        final store = PathRefStore();
        expect(() => store.dec('a'), returnsNormally);
        expect(store.inspect(), {});
      });

      test('Deep dec on an empty store is a no-op', () {
        final store = PathRefStore();
        expect(() => store.dec('a__b__c'), returnsNormally);
        expect(store.inspect(), {});
      });

      test('Decrementing past zero is a no-op', () {
        final store = PathRefStore();
        store.inc('a__b');
        store.dec('a__b');
        expect(() => store.dec('a__b'), returnsNormally);
        expect(store.inspect(), {});
      });
    });
  });
}
