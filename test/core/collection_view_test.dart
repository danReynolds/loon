import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';

import '../models/test_animal_model.dart';
import '../models/test_persistor.dart';
import '../utils.dart';

/// A view of the animals collection narrowed to dogs.
CollectionView<TestDogModel, TestAnimalModel> get dogs {
  return CollectionView(TestAnimalModel.store);
}

/// Matches a [DocumentSnapshotView] narrowed to dogs whose narrowed data is [data].
Matcher isDogView(TestDogModel? data) {
  return isA<DocumentSnapshotView<TestDogModel, TestAnimalModel>>().having(
    (view) => view.data,
    'data',
    data,
  );
}

void main() {
  setUp(() {
    Loon.configure(persistor: null);
  });

  tearDown(() async {
    Loon.unsubscribe();
    await Loon.clearAll();
  });

  group(
    'CollectionView',
    () {
      group(
        'doc',
        () {
          test('Returns a view of the document narrowed to the view type', () {
            final dog = TestDogModel('Dog 1');
            TestAnimalModel.store.doc('1').create(dog);

            final view = dogs.doc('1').get();

            expect(view, isDogView(dog));

            // The narrowed data is statically typed as the view type.
            final TestDogModel? data = view?.data;
            expect(data, dog);
          });
        },
      );

      group(
        'get',
        () {
          test('Returns an empty list when the collection is empty', () {
            expect(dogs.get(), isEmpty);
          });

          test(
            'Returns a view of every document, narrowing the data of documents of the view type',
            () {
              final dog = TestDogModel('Dog 1');
              final cat = TestCatModel('Cat 2');
              final dog3 = TestDogModel('Dog 3');

              TestAnimalModel.store.doc('1').create(dog);
              TestAnimalModel.store.doc('2').create(cat);
              TestAnimalModel.store.doc('3').create(dog3);

              expect(
                dogs.get(),
                [
                  isDogView(dog),
                  // Documents of other subtypes are included with null narrowed data.
                  isDogView(null),
                  isDogView(dog3),
                ],
              );
            },
          );
        },
      );

      group(
        'stream',
        () {
          test('Returns a stream of views of the collection', () async {
            final dog = TestDogModel('Dog 1');
            final dogUpdated = TestDogModel('Dog 1 updated');
            final cat = TestCatModel('Cat 2');
            final dogDoc = TestAnimalModel.store.doc('1');
            final catDoc = TestAnimalModel.store.doc('2');

            final stream = dogs.stream();

            await asyncEvent();
            dogDoc.create(dog);
            await asyncEvent();
            catDoc.create(cat);
            await asyncEvent();
            dogDoc.update(dogUpdated);
            await asyncEvent();
            dogDoc.delete();
            await asyncEvent();
            TestAnimalModel.store.delete();
            await asyncEvent();

            final events = await stream.take(6).toList();

            expect(
              events,
              [
                // No data
                [],
                // Dog 1 created
                [isDogView(dog)],
                // Cat 2 created
                [isDogView(dog), isDogView(null)],
                // Dog 1 updated
                [isDogView(dogUpdated), isDogView(null)],
                // Dog 1 deleted
                [isDogView(null)],
                // Animal collection deleted
                [],
              ],
            );
          });
        },
      );
    },
  );

  group(
    'DocumentView',
    () {
      group(
        'get',
        () {
          test('Returns null when the document does not exist', () {
            expect(dogs.doc('1').get(), isNull);
          });

          test(
            'Returns a view with narrowed data when the document is of the view type',
            () {
              final dog = TestDogModel('Dog 1');
              TestAnimalModel.store.doc('1').create(dog);

              expect(dogs.doc('1').get(), isDogView(dog));
            },
          );

          test(
            'Returns a view with null data when the document is a different subtype',
            () {
              TestAnimalModel.store.doc('1').create(TestCatModel('Cat 1'));

              final view = dogs.doc('1').get();

              expect(view, isNotNull);
              expect(view!.data, isNull);
            },
          );
        },
      );

      group(
        'stream',
        () {
          test('Returns a stream of document views', () async {
            final dog = TestDogModel('Dog 1');
            final dogUpdated = TestDogModel('Dog 1 updated');
            final cat = TestCatModel('Cat 1');
            final doc = TestAnimalModel.store.doc('1');

            final stream = dogs.doc('1').stream();

            await asyncEvent();
            doc.create(dog);
            await asyncEvent();
            doc.update(dogUpdated);
            await asyncEvent();
            doc.update(cat);
            await asyncEvent();
            doc.delete();
            await asyncEvent();

            final events = await stream.take(5).toList();

            expect(
              events,
              [
                // No data
                null,
                // Dog 1 created
                isDogView(dog),
                // Dog 1 updated
                isDogView(dogUpdated),
                // Dog 1 changed to a cat through the parent collection
                isDogView(null),
                // Dog 1 deleted
                null,
              ],
            );
          });
        },
      );
    },
  );

  group(
    'DocumentSnapshotView',
    () {
      group(
        'data',
        () {
          test('Returns the snapshot data when it is of the view type', () {
            final dog = TestDogModel('Dog 1');
            final snap = TestAnimalModel.store.doc('1').create(dog);

            expect(
              DocumentSnapshotView<TestDogModel, TestAnimalModel>(snap).data,
              dog,
            );
          });

          test('Returns null when the snapshot data is not of the view type',
              () {
            final snap =
                TestAnimalModel.store.doc('1').create(TestCatModel('Cat 1'));

            expect(
              DocumentSnapshotView<TestDogModel, TestAnimalModel>(snap).data,
              isNull,
            );
          });
        },
      );
    },
  );

  group(
    'Hydration',
    () {
      tearDown(() {
        Loon.configure(persistor: null);
      });

      test('Narrows documents lazily deserialized from persistence', () async {
        final dog = TestDogModel('Dog 1');
        final cat = TestCatModel('Cat 2');
        final dogDoc = TestAnimalModel.store.doc('1');
        final catDoc = TestAnimalModel.store.doc('2');

        Loon.configure(
          persistor: TestPersistor(
            seedData: [
              DocumentSnapshot(doc: dogDoc, data: dog),
              DocumentSnapshot(doc: catDoc, data: cat),
            ],
          ),
        );

        await Loon.hydrate();

        // Hydrated documents are stored as JSON until they are first read, at which point
        // they are deserialized through the parent collection and then narrowed by the view.
        expect(dogs.doc('1').get(), isDogView(dog));
        expect(dogs.doc('2').get(), isDogView(null));
        expect(dogs.get(), [isDogView(dog), isDogView(null)]);
      });
    },
  );
}
