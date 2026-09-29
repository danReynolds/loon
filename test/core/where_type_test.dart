// Ported from PR #41's collection_view_test.dart: the same behavioral guarantees, held against
// `whereType<S>()` handles that are ordinary Collection/Document/Query types.
import 'dart:math';

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

class CountingAnimalCollection extends Collection<TestAnimalModel> {
  CountingAnimalCollection() : super('', 'counted');
  int documentHandles = 0;
  int scans = 0;

  @override
  Document<TestAnimalModel> doc([String? id]) {
    documentHandles++;
    return super.doc(id);
  }

  @override
  List<DocumentSnapshot<TestAnimalModel>> get() {
    scans++;
    return super.get();
  }
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

  test('collection and query narrowing give equivalent typed reads', () {
    animals.doc('dog').create(const TestDogModel('Rex'));
    animals.doc('cat').create(const TestCatModel('Cat'));
    animals.doc('quiet').create(const TestDogModel('Q'));
    final Collection<TestDogModel> collection = dogs;
    final Query<TestDogModel> fromQuery =
        animals.toQuery().whereType<TestDogModel>();
    expect(fromQuery.get(), collection.get());
    expect(collection.get().map((s) => s.id), ['dog', 'quiet']);
    // Narrowing commutes with filters written against the base type.
    bool named(DocumentSnapshot<TestAnimalModel> s) => s.data.name.length > 1;
    expect(
      animals.where(named).whereType<TestDogModel>().get(),
      dogs.where(named).get(),
    );
    expect(dogs.where(named).get().single.id, 'dog');
    expect(dogs.doc('dog').get(), animals.doc('dog').get());
    expect(dogs.doc('cat').get(), isNull);
  });

  test('sorting and cached reads project each snapshot once', () {
    final source = CountingAnimalCollection();
    for (var i = 0; i < 2000; i++) {
      source
          .doc('$i')
          .create(TestDogModel('${(i * 997) % 2000}'), broadcast: false);
    }
    final view = source.whereType<TestDogModel>();
    final query = view
        .where((s) => s.data.barkVolume > 0)
        .sortBy((a, b) => a.data.name.compareTo(b.data.name));
    source.documentHandles = 0;
    final snaps = query.get();
    expect(snaps, hasLength(2000));
    // Projection, filtering and sorting create no source handles; a snapshot's document
    // creates one when it is first used.
    expect(source.documentHandles, 0);
    expect(snaps.first.doc.get(), snaps.first);
    expect(source.documentHandles, 1);
    final observed = query.observe();
    final first = observed.get();
    source.documentHandles = 0;
    for (var i = 0; i < 20; i++) {
      expect(observed.get(), same(first));
    }
    expect(view.exists(), isTrue);
    expect(source.documentHandles, 0);

    source.doc('0').update(const TestDogModel('Changed'));
    final updated = observed.get();
    expect(updated, isNot(same(first)));
    expect(updated.singleWhere((s) => s.id == '0').data.name, 'Changed');
    expect(first.singleWhere((s) => s.id == '0').data.name, '0');
    observed.dispose();
  });

  test('observed narrowings agree with fresh reads through mixed batched operations',
      () {
    fakeAsync((async) {
      final random = Random(41);
      final query = dogs
          .where((s) => s.data.barkVolume > 2)
          .sortBy((a, b) => a.data.name.compareTo(b.data.name));
      final observed = query.observe();
      final watched = dogs.doc('0').observe();
      List<DocumentSnapshot<TestDogModel>>? emitted;
      DocumentSnapshot<TestDogModel>? emittedDoc;
      observed.stream().listen((s) => emitted = s);
      watched.stream().listen((s) => emittedDoc = s);
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
          expect(watched.get(), dogs.doc('0').get());
        }
        flushBroadcasts(async);
        expect(emitted, query.get());
        expect(emittedDoc, dogs.doc('0').get());
      }
    });
  });

  test('selects subtype data through ordinary collection and document types',
      () {
    const dog = TestDogModel('Rex');
    animals.doc('dog').create(dog);
    animals.doc('cat').create(const TestCatModel('Mittens'));
    animals.doc('guide').create(const GuideDog('Guide'));

    final List<DocumentSnapshot<TestDogModel>> snaps = dogs.get();
    expect(snaps.map((s) => s.id), ['dog', 'guide']);
    expect(snaps.first.data, same(dog));
    expect(snaps.first.doc, dogs.doc('dog'));
    expect(snaps.first.path, animals.doc('dog').path);
    expect(snaps.first.doc, isA<Document<TestDogModel>>());
    expect(dogs, isA<Collection<TestDogModel>>());
    expect(dogs.path, animals.path);
    expect(dogs.parent, animals.parent);
    expect(dogs.name, animals.name);
    expect(dogs.exists(), isTrue);
    expect(dogs.doc('dog').exists(), isTrue);
    expect(dogs.doc('cat').get(), isNull);
    expect(dogs.doc('cat').exists(), isFalse);
    expect(dogs.doc('missing').get(), isNull);
    expect(dogs.whereType<GuideDog>().get().single.id, 'guide');

    animals.doc('dog').delete();
    animals.doc('guide').delete();
    expect(dogs.exists(), isFalse);
  });

  test('snapshot handles keep the source codec after writes through another type',
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

  test('observed results keep the source codec after writes through another type',
      () {
    fakeAsync((async) {
      final narrowWriter = Loon.collection<TestDogModel>('animals',
          fromJson: (json) => TestDogModel(json['name']),
          toJson: (dog) => dog.toJson());
      final observed = dogs.observe();
      var emitted = <DocumentSnapshot<TestDogModel>>[];
      observed.stream().listen((s) => emitted = s);
      flushBroadcasts(async);
      narrowWriter.doc('one').create(const TestDogModel('Rex'));
      flushBroadcasts(async);
      final handle = emitted.single.doc;
      animals.doc('one').update(const TestCatModel('Cat'));
      expect(handle.get(), isNull);
    });
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

  test('query callbacks receive subtype data and ordinary snapshots', () {
    animals.doc('one').create(const TestDogModel('Rex'));
    animals.doc('cat').create(const TestCatModel('A'));
    animals.doc('two').create(const TestDogModel('Alexander'));
    animals.doc('three').create(const TestDogModel('Rover'));
    final query = dogs
        .where((snap) => snap.data.barkVolume > 3)
        .sortBy((a, b) => b.data.barkVolume.compareTo(a.data.barkVolume))
        .where((snap) => snap.data.name.startsWith('R'));
    expect(query.get().map((s) => s.id), ['three']);
    expect(query.get().single.doc, isA<Document<TestDogModel>>());
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
      final collectionChanges = <DocumentChangeSnapshot<TestDogModel>>[];
      final documentChanges = <DocumentChangeSnapshot<TestDogModel>>[];
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
      expect(document.observe(), same(document));
      expect(collection.observe(), same(collection));
    });
  });

  test('narrowed predicates and ordering stay live through source writes', () {
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

  test('reads between batched writes cannot leave stale caches', () {
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
      final changes = <DocumentChangeSnapshot<TestDogModel>>[];
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

  test('ancestor deletion removes nested narrowings and observed documents',
      () {
    fakeAsync((async) {
      final parent = Loon.collection<int>('parents').doc('one');
      parent.create(1, broadcast: false);
      final source = parent.subcollection<TestAnimalModel>('animals');
      source.doc('dog').create(const TestDogModel('Rex'), broadcast: false);
      final view = source.whereType<TestDogModel>();
      final changes = <DocumentChangeSnapshot<TestDogModel>>[];
      view.doc('dog').streamChanges().listen(changes.add);
      final obs = view.observe();
      parent.delete();
      flushBroadcasts(async);
      expect(obs.get(), isEmpty);
      expect(changes.single.event, BroadcastEvents.removed);
      expect(changes.single.prevData, const TestDogModel('Rex'));
    });
  });

  test('hydration uses the source codec; ID reads and observation avoid scans',
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

  test('streams retain identity and release their observer on cancellation',
      () {
    fakeAsync((async) {
      final query = dogs.observe();
      final doc = dogs.doc('dog').observe();
      // Controller streams compare equal per controller, which is what StreamBuilder checks.
      expect(query.stream(), query.stream());
      expect(query.streamChanges(), query.streamChanges());
      expect(doc.stream(), doc.stream());
      expect(doc.streamChanges(), doc.streamChanges());
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

  testWidgets('existing builders accept narrowings and switch sources',
      (tester) async {
    final cats = animals.whereType<TestCatModel>();
    animals.doc('one').create(const TestDogModel('Rex'), broadcast: false);
    Widget screen(Document<TestAnimalModel> doc,
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

  testWidgets('inline narrowings are observed once across rebuilds',
      (tester) async {
    final source = CountingAnimalCollection();
    source.doc('rex').create(const TestDogModel('Rex'), broadcast: false);
    Widget screen(int build) => MaterialApp(
          home: Column(children: [
            Text('build:$build'),
            QueryStreamBuilder(
              query: source.whereType<TestDogModel>(),
              builder: (_, snaps) => Text('dogs:${snaps.length}'),
            ),
            DocumentStreamBuilder(
              doc: source.whereType<TestDogModel>().doc('rex'),
              builder: (_, snap) => Text('rex:${snap?.data.name}'),
            ),
          ]),
        );
    await tester.pumpWidget(screen(0));
    final initialScans = source.scans;
    for (var build = 1; build <= 10; build++) {
      await tester.pumpWidget(screen(build));
    }
    // New narrowed handles compare equal by path and type, so neither builder re-observes.
    expect(source.scans, initialScans);
    expect(find.text('dogs:1'), findsOneWidget);
    expect(find.text('rex:Rex'), findsOneWidget);
  });

  // Beyond the PR's suite: narrowed handles are writable.

  test('narrowed writes use the source codec and only affect their type', () {
    fakeAsync((async) {
      final batches = <Set<Document>>[];
      Loon.configure(persistor: TestPersistor(onPersist: batches.add));
      elapseAndFlush(async, const Duration(milliseconds: 1));

      final created = dogs.doc('rex').create(const TestDogModel('Rex'));
      expect(created, isA<DocumentSnapshot<TestDogModel>>());
      animals.doc('cat').create(const TestCatModel('Mittens'));
      elapseAndFlush(async, const Duration(milliseconds: 1));

      // The write went through the source's handle, so persistence serializes with its codec.
      final persisted = batches.expand((b) => b).firstWhere((d) => d.id == 'rex');
      expect(persisted, isA<Document<TestAnimalModel>>());
      expect(persisted, isNot(isA<Document<TestDogModel>>()));
      expect(persisted.getSerialized(), {'type': 'dog', 'name': 'Rex'});

      final modified =
          dogs.doc('rex').modify((snap) => TestDogModel('${snap.data.name}!'));
      expect(modified.data.name, 'Rex!');
      expect(animals.doc('rex').get()!.data, const TestDogModel('Rex!'));

      // Other types are absent: a narrowed handle neither updates nor deletes them.
      expect(() => dogs.doc('cat').update(const TestDogModel('Nope')),
          throwsException);
      expect(() => dogs.doc('cat').modify((s) => s.data), throwsException);
      dogs.doc('cat').delete();
      expect(animals.doc('cat').get()!.data, const TestCatModel('Mittens'));
      // An ID taken by another type is never overwritten.
      expect(() => dogs.doc('cat').create(const TestDogModel('Nope')),
          throwsException);
      expect(() => dogs.doc('cat').createOrUpdate(const TestDogModel('Nope')),
          throwsException);

      dogs.replace([
        DocumentSnapshot(
            doc: dogs.doc('fido'), data: const TestDogModel('Fido')),
      ]);
      expect(animals.get().map((s) => s.id), unorderedEquals(['cat', 'fido']));
      // A replacement that would overwrite another type fails before writing anything.
      expect(
          () => dogs.replace([
                DocumentSnapshot(
                    doc: dogs.doc('cat'), data: const TestDogModel('Nope')),
              ]),
          throwsException);
      expect(animals.get().map((s) => s.id), unorderedEquals(['cat', 'fido']));
      dogs.delete();
      expect(animals.get().map((s) => s.id), ['cat']);
    });
  });

  test('transactions roll back narrowed and source writes to the same document',
      () async {
    animals.doc('x').create(const TestDogModel('Rex'));
    await expectLater(
      Loon.transaction((writer) async {
        writer.update(dogs.doc('x'), const TestDogModel('Rex 2'));
        writer.update(animals.doc('x'), const TestCatModel('Cat'));
        throw StateError('abort');
      }),
      throwsStateError,
    );
    expect(animals.doc('x').get()!.data, const TestDogModel('Rex'));

    await expectLater(
      Loon.transaction((writer) async {
        writer.create(dogs.doc('y'), const TestDogModel('New'));
        throw StateError('abort');
      }),
      throwsStateError,
    );
    expect(animals.doc('y').exists(), isFalse);
  });

  testWidgets('builder snapshots from a narrowing are writable', (tester) async {
    animals.doc('rex').create(const TestDogModel('Rex'), broadcast: false);
    List<DocumentSnapshot<TestDogModel>> latest = [];
    await tester.pumpWidget(MaterialApp(
      home: QueryStreamBuilder<TestDogModel>(
        query: dogs,
        builder: (_, snaps) {
          latest = snaps;
          return Text(snaps.map((s) => s.data.name).join(','));
        },
      ),
    ));
    expect(find.text('Rex'), findsOneWidget);
    latest.single.doc.update(TestDogModel('${latest.single.data.name}!'));
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(find.text('Rex!'), findsOneWidget);
  });
}
