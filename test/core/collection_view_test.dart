import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';

import '../models/test_animal_model.dart';
import '../models/test_persistor.dart';
import '../utils.dart';

class GuideDog extends TestDogModel {
  const GuideDog(super.name);
}

void main() {
  final animals = TestAnimalModel.store;
  final dogs = animals.whereType<TestDogModel>();

  setUp(() => Loon.configure(persistor: null));
  tearDown(() async {
    Loon.unsubscribe();
    Loon.configure(persistor: null);
    await Loon.clearAll(broadcast: false);
  });

  test('selects subtype data and exposes read-only document handles', () {
    const dog = TestDogModel('Rex');
    animals.doc('dog').create(dog);
    animals.doc('cat').create(const TestCatModel('Mittens'));
    animals.doc('guide').create(const GuideDog('Guide'));

    final List<DocumentSnapshotView<TestDogModel>> snaps = dogs.get();
    expect(snaps.map((s) => s.id), ['dog', 'guide']);
    expect(snaps.first.data, same(dog));
    expect(snaps.first.doc, dogs.doc('dog'));
    expect(snaps.first.path, animals.doc('dog').path);
    expect(snaps.first.doc, isNot(isA<Document>()));
    expect(dogs, isNot(isA<Collection>()));
    expect(dogs.path, animals.path);
    expect(dogs.parent, animals.parent);
    expect(dogs.name, animals.name);
    expect(dogs.exists(), isTrue);
    expect(dogs.doc('dog').exists(), isTrue);
    expect(dogs.doc('cat').get(), isNull);
    expect(dogs.doc('cat').exists(), isFalse);
    expect(dogs.doc('missing').get(), isNull);
    expect(dogs.whereType<GuideDog>().get().single.id, 'guide');
    expect(dogs.doc('dog'), isNot(animals.whereType<GuideDog>().doc('dog')));

    animals.doc('dog').delete();
    animals.doc('guide').delete();
    expect(dogs.exists(), isFalse);
  });

  test(
      'snapshot handles keep the parent codec after writes through another type',
      () {
    final narrowWriter = Loon.collection<TestDogModel>('animals',
        fromJson: (json) => TestDogModel(json['name']),
        toJson: (dog) => dog.toJson());
    narrowWriter.doc('one').create(const TestDogModel('Rex'));
    final handle = dogs.get().single.doc;
    animals.doc('one').update(const TestCatModel('Cat'));
    expect(handle.get(), isNull);
    animals.doc('one').update(const TestDogModel('Back'));
    expect(handle.get()!.data.name, 'Back');
  });

  test('missing nullable documents remain absent', () {
    final source = Loon.collection<Object?>('nullable');
    final view = source.whereType<String?>();
    expect(view.doc('missing').get(), isNull);
    source.doc('null').create(null);
    expect(view.doc('null').get(), isNotNull);
    expect(view.doc('null').get()!.data, isNull);
    expect(view.get().single.id, 'null');
  });

  test('query callbacks receive subtype data and read-only snapshots', () {
    animals.doc('one').create(const TestDogModel('Rex'));
    animals.doc('cat').create(const TestCatModel('A'));
    animals.doc('two').create(const TestDogModel('Alexander'));
    animals.doc('three').create(const TestDogModel('Rover'));
    final query = dogs
        .where((snap) => snap.data.barkVolume > 3)
        .sortBy((a, b) => b.data.barkVolume.compareTo(a.data.barkVolume))
        .where((snap) => snap.data.name.startsWith('R'));
    expect(query.get().map((s) => s.id), ['three']);
    expect(query.get().single.doc, isNot(isA<Document>()));
    expect(query.toQuery(), same(query));
  });

  test('collection and document observations share subtype membership events',
      () {
    fakeAsync((async) {
      final doc = animals.doc('one');
      final collection = dogs.observe();
      final document = dogs.doc('one').observe();
      final lists = <List<String>>[];
      final values = <String?>[];
      final collectionChanges = <DocumentChangeSnapshotView<TestDogModel>>[];
      final documentChanges = <DocumentChangeSnapshotView<TestDogModel>>[];
      collection
          .stream()
          .listen((s) => lists.add(s.map((s) => s.data.name).toList()));
      collection.streamChanges().listen(collectionChanges.addAll);
      document.stream().listen((s) => values.add(s?.data.name));
      document.streamChanges().listen(documentChanges.add);
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
      expect(documentChanges, collectionChanges);
      expect(documentChanges.map((s) => s.event), [
        BroadcastEvents.added,
        BroadcastEvents.modified,
        BroadcastEvents.removed,
        BroadcastEvents.added,
        BroadcastEvents.removed,
      ]);
      expect(documentChanges[2].prevData, const TestDogModel('Updated'));
      expect(documentChanges[2].data, isNull);
      expect(documentChanges.first.doc, dogs.doc('one'));
      expect(documentChanges.first.doc, isNot(isA<Document>()));
      expect(document.observe(), same(document));
      expect(collection.observe(), same(collection));
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
      final document = dogs.doc('one').observe();
      final emissions = <String?>[];
      document.stream().listen((s) => emissions.add(s?.data.name));
      flushBroadcasts(async);
      doc.update(const TestCatModel('Cat'));
      expect(document.get(), isNull);
      expect(collection.get(), isEmpty);
      doc.update(const TestDogModel('Last'));
      expect(document.get()!.data.name, 'Last');
      expect(collection.get().single.data.name, 'Last');
      flushBroadcasts(async);
      expect(emissions, ['First', 'Last']);
      expect(document.get()!.data.name, 'Last');
    });
  });

  test('delete and recreate as another subtype evicts the old member', () {
    fakeAsync((async) {
      final doc = animals.doc('one');
      doc.create(const TestDogModel('First'), broadcast: false);
      final obs = dogs.doc('one').observe();
      final changes = <DocumentChangeSnapshotView<TestDogModel>>[];
      obs.streamChanges().listen(changes.add);
      doc.delete();
      doc.create(const TestCatModel('Cat'));
      flushBroadcasts(async);
      expect(obs.get(), isNull);
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
          .whereType<TestDogModel>()
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
      final view = source.whereType<TestDogModel>();
      final changes = <DocumentChangeSnapshotView<TestDogModel>>[];
      view.doc('dog').streamChanges().listen(changes.add);
      final obs = view.observe();
      parent.delete();
      flushBroadcasts(async);
      expect(obs.get(), isEmpty);
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
    final view = source.whereType<TestDogModel>();
    expect(view.doc('missing').get(), isNull);
    expect(parsed, 0);
    final obs = view.doc('dog').observe();
    expect(obs.get()!.data.name, 'Rex');
    expect(parsed, 1);
    expect(view.doc('cat').get(), isNull);
    expect(parsed, 2);
    expect(view.get().map((s) => s.id), ['dog', 'other']);
    expect(parsed, 3);
    obs.dispose();
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
    final document = dogs.doc('dog').observe();
    final queryEvent = query.stream().firstWhere((s) => s.isNotEmpty);
    final documentEvent = document.stream().firstWhere((s) => s != null);
    await Loon.hydrate();
    expect((await queryEvent).single.data, const TestDogModel('Rex'));
    expect((await documentEvent)!.data, const TestDogModel('Rex'));
  });

  test(
      'projected streams retain identity and release their observer on cancellation',
      () {
    fakeAsync((async) {
      final query = dogs.observe();
      final doc = dogs.doc('dog').observe();
      expect(query.stream(), same(query.stream()));
      expect(query.streamChanges(), same(query.streamChanges()));
      expect(doc.stream(), same(doc.stream()));
      expect(doc.streamChanges(), same(doc.streamChanges()));
      final a = query.stream().listen((_) {});
      final b = doc.streamChanges().listen((_) {});
      a.cancel();
      b.cancel();
      flushBroadcasts(async);
      expect(Loon.inspect()['broadcastStore']['observerValues'], isEmpty);
    });
  });

  test('multicast supports independent listeners and explicit disposal', () {
    fakeAsync((async) {
      final obs = dogs.doc('dog').observe(multicast: true);
      final first = <String?>[];
      final second = <String?>[];
      final a = obs.stream().listen((s) => first.add(s?.data.name));
      final b = obs.stream().listen((s) => second.add(s?.data.name));
      expect(obs.multicast, isTrue);
      animals.doc('dog').create(const TestDogModel('First'));
      flushBroadcasts(async);
      a.cancel();
      flushBroadcasts(async);
      animals.doc('dog').update(const TestDogModel('Second'));
      flushBroadcasts(async);
      expect(first, ['First']);
      expect(second, ['First', 'Second']);
      var done = false;
      b.onDone(() => done = true);
      obs.dispose();
      obs.dispose();
      flushBroadcasts(async);
      expect(done, isTrue);
    });
  });

  testWidgets('existing builders accept views, switch sources, and dispose',
      (tester) async {
    final cats = animals.whereType<TestCatModel>();
    animals.doc('one').create(const TestDogModel('Rex'), broadcast: false);
    Widget screen(DocumentView<TestAnimalModel> doc,
            Queryable<TestAnimalModel> query) =>
        MaterialApp(
            home: Column(children: [
          DocumentStreamBuilder(
              doc: doc,
              builder: (_, snap) =>
                  Text('doc:${snap?.data.name ?? "missing"}')),
          QueryStreamBuilder(
              query: query,
              builder: (_, snaps) =>
                  Text('list:${snaps.map((s) => s.data.name).join(",")}')),
        ]));
    await tester.pumpWidget(screen(dogs.doc('one'), dogs));
    expect(find.text('doc:Rex'), findsOneWidget);
    expect(find.text('list:Rex'), findsOneWidget);
    // Rebuilding with the same views must not resubscribe to a new mapped stream.
    await tester.pumpWidget(screen(dogs.doc('one'), dogs));
    await tester.pump();
    expect(tester.takeException(), isNull);
    animals.doc('one').update(const TestCatModel('Mittens'));
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(find.text('doc:missing'), findsOneWidget);
    expect(find.text('list:'), findsOneWidget);
    await tester.pumpWidget(screen(cats.doc('one'), cats));
    await tester.pump();
    expect(find.text('doc:Mittens'), findsOneWidget);
    expect(find.text('list:Mittens'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    animals.doc('one').update(const TestDogModel('Back'));
    await tester.pump(const Duration(milliseconds: 1));
    expect(tester.takeException(), isNull);
  });
}
