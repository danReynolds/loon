import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';

import '../models/test_animal_model.dart';
import '../models/test_persistor.dart';
import '../utils.dart';

class GuideDog extends TestDogModel {
  const GuideDog(super.name);
}

class CountingAnimalCollection extends Collection<TestAnimalModel> {
  CountingAnimalCollection() : super('', 'counted');
  int documentHandles = 0;

  @override
  Document<TestAnimalModel> doc([String? id]) {
    documentHandles++;
    return super.doc(id);
  }
}

void main() {
  final animals = TestAnimalModel.store;
  final dogs = animals.view<TestDogModel>();

  setUp(() => Loon.configure(persistor: null));
  tearDown(() async {
    Loon.unsubscribe();
    Loon.configure(persistor: null);
    await Loon.clearAll(broadcast: false);
  });

  test('views of the same subtype give equivalent typed reads', () {
    animals.doc('dog').create(const TestDogModel('Rex'));
    animals.doc('cat').create(const TestCatModel('Cat'));
    final again = animals.view<TestDogModel>();
    final CollectionView<TestDogModel> inferred = animals.view();
    expect(again.get(), dogs.get());
    expect(inferred.get(), dogs.get());
    expect(inferred.doc('dog').get(), dogs.doc('dog').get());
    expect(dogs.doc('cat').get(), isNull);
    expect(again.where((s) => s.data.barkVolume > 0).path, animals.path);
  });

  test('document views compare equal by document and subtype', () {
    expect(dogs.doc('dog'), animals.view<TestDogModel>().doc('dog'));
    expect(dogs.doc('dog').hashCode,
        animals.view<TestDogModel>().doc('dog').hashCode);
    expect(dogs.doc('dog'), isNot(animals.view<GuideDog>().doc('dog')));
    expect(dogs.doc('dog'), isNot(dogs.doc('other')));
  });

  test('a view keeps its subtype when its static type is widened', () {
    animals.doc('dog').create(const TestDogModel('Rex'));
    animals.doc('cat').create(const TestCatModel('Cat'));
    final CollectionView<TestAnimalModel> widened = dogs;
    expect(widened.get().map((s) => s.id), ['dog']);
    expect(widened.doc('cat').get(), isNull);
  });

  test('sorting and cached reads use the store snapshots without copies', () {
    final source = CountingAnimalCollection();
    for (var i = 0; i < 2000; i++) {
      source
          .doc('$i')
          .create(TestDogModel('${(i * 997) % 2000}'), broadcast: false);
    }
    final view = source.view<TestDogModel>();
    final query = view
        .where((s) => s.data.barkVolume > 0)
        .sortBy((a, b) => a.data.name.compareTo(b.data.name));
    source.documentHandles = 0;
    expect(query.get(), hasLength(2000));
    // Reads, filters and comparisons create no handles or projections.
    expect(source.documentHandles, 0);
    final observed = query.observe();
    final first = observed.get();
    for (var i = 0; i < 20; i++) {
      expect(observed.get(), same(first));
    }
    expect(view.get(), isNotEmpty);
    expect(source.documentHandles, 0);

    source.doc('0').update(const TestDogModel('Changed'));
    final updated = observed.get();
    expect(updated, isNot(same(first)));
    expect(updated.singleWhere((s) => s.id == '0').data.name, 'Changed');
    expect(first.singleWhere((s) => s.id == '0').data.name, '0');
    observed.dispose();
  });

  test('observed views agree with fresh reads through mixed batched operations',
      () {
    fakeAsync((async) {
      final random = Random(41);
      final query = dogs
          .where((s) => s.data.barkVolume > 2)
          .sortBy((a, b) => a.data.name.compareTo(b.data.name));
      final observed = query.observe();
      List<DocumentSnapshotView<TestDogModel>>? emitted;
      DocumentSnapshotView<TestDogModel>? emittedDoc;
      observed.stream().listen((s) => emitted = s);
      dogs.doc('0').stream().listen((s) => emittedDoc = s);
      flushBroadcasts(async);
      for (var batch = 0; batch < 80; batch++) {
        for (var write = 0; write < 3; write++) {
          final id = '${random.nextInt(8)}';
          final doc = animals.doc(id);
          switch (random.nextInt(5)) {
            case 0:
              doc.delete();
              break;
            case 1:
              doc.createOrUpdate(TestCatModel('cat$batch'));
              break;
            case 2:
              animals.delete();
              break;
            default:
              doc.createOrUpdate(
                  TestDogModel(random.nextBool() ? 'a' : 'dog$batch'));
          }
          expect(observed.get(), query.get());
        }
        flushBroadcasts(async);
        expect(emitted, query.get());
        expect(emittedDoc, dogs.doc('0').get());
      }
    });
  });

  test('selects subtype data', () {
    const rex = TestDogModel('Rex');
    animals.doc('dog').create(rex);
    animals.doc('cat').create(const TestCatModel('Mittens'));
    animals.doc('guide').create(const GuideDog('Guide'));

    final List<DocumentSnapshotView<TestDogModel>> snaps = dogs.get();
    expect(snaps.map((s) => s.id), ['dog', 'guide']);
    expect(snaps.first.data, same(rex));
    // A view snapshot is the store's own snapshot.
    expect(snaps.first as Object, same(animals.doc('dog').get()));
    expect(snaps.first.path, animals.doc('dog').path);
    expect(dogs.path, animals.path);
    expect(dogs.doc('dog').exists(), isTrue);
    expect(dogs.doc('cat').get(), isNull);
    expect(dogs.doc('cat').exists(), isFalse);
    expect(dogs.doc('missing').get(), isNull);
    expect(animals.view<GuideDog>().get().single.id, 'guide');

    animals.doc('dog').delete();
    animals.doc('guide').delete();
    expect(dogs.get(), isEmpty);
  });

  test('document views keep the parent codec after writes through another type',
      () {
    final narrowWriter = Loon.collection<TestDogModel>('animals',
        fromJson: (json) => TestDogModel(json['name']),
        toJson: (dog) => dog.toJson());
    narrowWriter.doc('one').create(const TestDogModel('Rex'));
    final handle = dogs.doc('one');
    expect(handle.get()!.data.name, 'Rex');
    animals.doc('one').update(const TestCatModel('Cat'));
    expect(handle.get(), isNull);
    animals.doc('one').update(const TestDogModel('Back'));
    expect(handle.get()!.data.name, 'Back');
  });

  test('missing nullable documents remain absent', () {
    final source = Loon.collection<Object?>('nullable');
    final view = source.view<String?>();
    expect(view.doc('missing').get(), isNull);
    source.doc('null').create(null);
    expect(view.doc('null').get(), isNotNull);
    expect(view.doc('null').get()!.data, isNull);
    expect(view.get().single.id, 'null');
  });

  test('query callbacks receive subtype data', () {
    animals.doc('one').create(const TestDogModel('Rex'));
    animals.doc('cat').create(const TestCatModel('A'));
    animals.doc('two').create(const TestDogModel('Alexander'));
    animals.doc('three').create(const TestDogModel('Rover'));
    final query = dogs
        .where((snap) => snap.data.barkVolume > 3)
        .sortBy((a, b) => b.data.barkVolume.compareTo(a.data.barkVolume))
        .where((snap) => snap.data.name.startsWith('R'));
    expect(query.get().map((s) => s.id), ['three']);
  });

  test('collection and document observations share subtype membership', () {
    fakeAsync((async) {
      final doc = animals.doc('one');
      final collection = dogs.observe();
      final lists = <List<String>>[];
      final values = <String?>[];
      final changes = <DocumentChangeSnapshotView<TestDogModel>>[];
      collection
          .stream()
          .listen((s) => lists.add(s.map((s) => s.data.name).toList()));
      collection.streamChanges().listen(changes.addAll);
      dogs.doc('one').stream().listen((s) => values.add(s?.data.name));
      flushBroadcasts(async);

      doc.create(const TestCatModel('Cat'));
      flushBroadcasts(async);
      doc.update(const TestDogModel('Dog'));
      flushBroadcasts(async);
      doc.update(const TestDogModel('Updated'));
      flushBroadcasts(async);
      doc.update(const TestCatModel('Cat again'));
      flushBroadcasts(async);
      doc.update(const TestCatModel('Still cat'));
      flushBroadcasts(async);
      doc.update(const TestDogModel('Dog again'));
      flushBroadcasts(async);
      doc.delete();
      flushBroadcasts(async);

      expect(lists, [
        [],
        ['Dog'],
        ['Updated'],
        [],
        ['Dog again'],
        []
      ]);
      expect(values, [null, 'Dog', 'Updated', null, 'Dog again', null]);
      expect(changes.map((s) => s.event), [
        BroadcastEvents.added,
        BroadcastEvents.modified,
        BroadcastEvents.removed,
        BroadcastEvents.added,
        BroadcastEvents.removed,
      ]);
      expect(changes[2].prevData, const TestDogModel('Updated'));
      expect(changes[2].data, isNull);
      expect(changes.first.id, 'one');
      expect(collection.observe(), collection);
    });
  });

  test('view predicates and ordering stay live through parent writes', () {
    fakeAsync((async) {
      final query = dogs
          .where((s) => s.data.barkVolume > 3)
          .sortBy((a, b) => a.data.name.compareTo(b.data.name));
      final emissions = <List<String>>[];
      query
          .stream()
          .listen((snaps) => emissions.add(snaps.map((s) => s.id).toList()));
      animals.doc('one').create(const TestDogModel('Zebra'));
      animals.doc('two').create(const TestDogModel('Bravo'));
      animals.doc('cat').create(const TestCatModel('Alpha'));
      flushBroadcasts(async);
      animals.doc('one').update(const TestDogModel('Alfa'));
      flushBroadcasts(async);
      animals.doc('two').update(const TestDogModel('Bo'));
      flushBroadcasts(async);
      expect(emissions, [
        [],
        ['two', 'one'],
        ['one', 'two'],
        ['one']
      ]);
    });
  });

  test('reads between batched writes cannot leave stale view caches', () {
    fakeAsync((async) {
      final doc = animals.doc('one');
      doc.create(const TestDogModel('First'), broadcast: false);
      final collection = dogs.observe();
      final emissions = <String?>[];
      dogs.doc('one').stream().listen((s) => emissions.add(s?.data.name));
      flushBroadcasts(async);
      doc.update(const TestCatModel('Cat'));
      expect(dogs.doc('one').get(), isNull);
      expect(collection.get(), isEmpty);
      doc.update(const TestDogModel('Last'));
      expect(dogs.doc('one').get()!.data.name, 'Last');
      expect(collection.get().single.data.name, 'Last');
      flushBroadcasts(async);
      expect(emissions, ['First', 'Last']);
    });
  });

  test('delete and recreate as another subtype evicts the old member', () {
    fakeAsync((async) {
      final doc = animals.doc('one');
      doc.create(const TestDogModel('First'), broadcast: false);
      final obs = dogs.observe();
      final changes = <DocumentChangeSnapshotView<TestDogModel>>[];
      obs.streamChanges().listen(changes.addAll);
      final values = <String?>[];
      dogs.doc('one').stream().listen((s) => values.add(s?.data.name));
      flushBroadcasts(async);
      doc.delete();
      doc.create(const TestCatModel('Cat'));
      flushBroadcasts(async);
      expect(obs.get(), isEmpty);
      expect(values, ['First', null]);
      expect(changes.single.event, BroadcastEvents.removed);
      expect(changes.single.prevData, const TestDogModel('First'));
    });
  });

  test(
      'dependency writes re-evaluate typed filters and invalidate cached reads',
      () {
    fakeAsync((async) {
      final flag = Loon.collection<bool>('flags').doc('visible');
      flag.create(true, broadcast: false);
      final dependentAnimals = Loon.collection<TestAnimalModel>('dependent',
          dependenciesBuilder: (_) => {flag});
      dependentAnimals
          .doc('one')
          .create(const TestDogModel('Rex'), broadcast: false);
      dependentAnimals
          .doc('cat')
          .create(const TestCatModel('Cat'), broadcast: false);
      final query = dependentAnimals
          .view<TestDogModel>()
          .where((s) => flag.get()!.data && s.data.barkVolume > 0);
      final obs = query.observe();
      final events = <List<String>>[];
      obs.stream().listen((s) => events.add(s.map((s) => s.id).toList()));
      flushBroadcasts(async);
      flag.update(false);
      expect(obs.get(), isEmpty);
      flag.update(true);
      flushBroadcasts(async);
      expect(obs.get(), query.get());
      expect(events, [
        ['one'],
        ['one']
      ]);
    });
  });

  test('ancestor deletion removes nested views and observed documents', () {
    fakeAsync((async) {
      final parent = Loon.collection<int>('parents').doc('one');
      parent.create(1, broadcast: false);
      final source = parent.subcollection<TestAnimalModel>('animals');
      source.doc('dog').create(const TestDogModel('Rex'), broadcast: false);
      final view = source.view<TestDogModel>();
      final values = <String?>[];
      view.doc('dog').stream().listen((s) => values.add(s?.data.name));
      final obs = view.observe();
      final changes = <DocumentChangeSnapshotView<TestDogModel>>[];
      obs.streamChanges().listen(changes.addAll);
      flushBroadcasts(async);
      parent.delete();
      flushBroadcasts(async);
      expect(obs.get(), isEmpty);
      expect(values, ['Rex', null]);
      expect(changes.single.event, BroadcastEvents.removed);
      expect(changes.single.prevData, const TestDogModel('Rex'));
    });
  });

  test('hydration uses the parent codec; ID reads and observation avoid scans',
      () async {
    var parsed = 0;
    final source = Loon.collection<TestAnimalModel>('hydrated',
        fromJson: (json) {
          parsed++;
          return TestAnimalModel.fromJson(json);
        },
        toJson: (animal) => animal.toJson());
    Loon.configure(
        persistor: TestPersistor(seedData: [
      DocumentSnapshot(doc: source.doc('dog'), data: const TestDogModel('Rex')),
      DocumentSnapshot(
          doc: source.doc('other'), data: const TestDogModel('Other')),
      DocumentSnapshot(doc: source.doc('cat'), data: const TestCatModel('Cat')),
    ]));
    await Loon.hydrate();
    final view = source.view<TestDogModel>();
    expect(view.doc('missing').get(), isNull);
    expect(parsed, 0);
    final first = view.doc('dog').stream().first;
    expect((await first)!.data.name, 'Rex');
    expect(parsed, 1);
    expect(view.doc('cat').get(), isNull);
    expect(parsed, 2);
    expect(view.get().map((s) => s.id), ['dog', 'other']);
    expect(parsed, 3);
  });

  test('observers started before hydration receive narrowed persisted data',
      () async {
    Loon.configure(
        persistor: TestPersistor(seedData: [
      DocumentSnapshot(
          doc: animals.doc('dog'), data: const TestDogModel('Rex')),
      DocumentSnapshot(
          doc: animals.doc('cat'), data: const TestCatModel('Cat')),
    ]));
    final query = dogs.observe();
    final queryEvent = query.stream().firstWhere((s) => s.isNotEmpty);
    final documentEvent = dogs.doc('dog').stream().firstWhere((s) => s != null);
    await Loon.hydrate();
    expect((await queryEvent).single.data, const TestDogModel('Rex'));
    expect((await documentEvent)!.data, const TestDogModel('Rex'));
  });

  test('observed streams are the query streams and release on cancellation',
      () {
    fakeAsync((async) {
      final query = dogs.observe();
      // The view's streams are its query's own, which compare equal per observer.
      expect(query.stream(), query.stream());
      expect(query.streamChanges(), query.streamChanges());
      final a = query.stream().listen((_) {});
      final b = dogs.doc('dog').stream().listen((_) {});
      a.cancel();
      b.cancel();
      flushBroadcasts(async);
      expect(Loon.inspect()['broadcastStore']['observerValues'], isEmpty);
    });
  });

  test('multicast supports independent listeners and explicit disposal', () {
    fakeAsync((async) {
      final obs = dogs.observe(multicast: true);
      final first = <List<String>>[];
      final second = <List<String>>[];
      final a = obs
          .stream()
          .listen((s) => first.add(s.map((s) => s.data.name).toList()));
      final b = obs
          .stream()
          .listen((s) => second.add(s.map((s) => s.data.name).toList()));
      expect(obs.multicast, isTrue);
      animals.doc('dog').create(const TestDogModel('First'));
      flushBroadcasts(async);
      a.cancel();
      flushBroadcasts(async);
      animals.doc('dog').update(const TestDogModel('Second'));
      flushBroadcasts(async);
      expect(first, [
        ['First']
      ]);
      expect(second, [
        ['First'],
        ['Second']
      ]);
      var done = false;
      b.onDone(() => done = true);
      obs.dispose();
      obs.dispose();
      flushBroadcasts(async);
      expect(done, isTrue);
    });
  });
}
