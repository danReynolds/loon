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

      test('Dec of untracked sibling path leaves tracked paths intact', () {
        final store = PathRefStore();
        store.inc('a__b');

        store.dec('a__c');

        expect(store.has('a__b'), true);
        expect(store.inspect(), {
          "__ref": 1,
          "a": {"__ref": 1, "b": 1},
        });
      });

      test('Dec of a path that became transient removes it fully', () {
        // Regression: inc'ing a path and a descendant, then dec'ing the
        // descendant, leaves the path as a transient node. Dec'ing the path
        // itself must remove it; previously the Map branch of `_dec` signalled
        // removal via a return value that the top-level `dec` ignored, so the
        // node lingered (has stayed true) and ref counts leaked. A second live
        // path keeps the root ref count above 1 so the early return doesn't
        // mask the bug.
        final store = PathRefStore();
        store.inc('c');
        store.inc('c__c');
        store.dec('c__c');
        store.inc('a');

        store.dec('c');

        expect(store.has('c'), false);
        expect(store.inspect(), {
          "__ref": 1,
          "a": 1,
        });
      });

      test('Dec of untracked deep path under a tracked node is a no-op', () {
        final store = PathRefStore();
        store.inc('a__b__c');

        store.dec('a__b__d');

        expect(store.has('a__b__c'), true);
        expect(store.inspect(), {
          "__ref": 1,
          "a": {
            "__ref": 1,
            "b": {"__ref": 1, "c": 1},
          },
        });
      });

      test('Dec of untracked ancestor path leaves descendants intact', () {
        final store = PathRefStore();
        store.inc('a__b');
        store.inc('x');

        store.dec('a');

        expect(store.has('a__b'), true);
        expect(store.inspect(), {
          "__ref": 2,
          "a": {"__ref": 1, "b": 1},
          "x": 1,
        });

        expect(() => store.dec('a__b'), returnsNormally);
        expect(store.inspect(), {
          "__ref": 1,
          "x": 1,
        });
      });
    });
  });
}
