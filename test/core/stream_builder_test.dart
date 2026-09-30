import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';

import '../models/test_animal_model.dart';

/// Stream builders dispose the observers they create, and leave the lifetime of an observer
/// passed in by the caller to the caller.
void main() {
  final animals = TestAnimalModel.store;
  final dogs = animals.view<TestDogModel>();

  tearDown(() async {
    Loon.unsubscribe();
    await Loon.clearAll(broadcast: false);
  });

  Future<void> flush(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
  }

  testWidgets('removing a query builder keeps a caller-owned observer open',
      (tester) async {
    final things = Loon.collection<String>('things');
    things.doc('one').create('a', broadcast: false);
    final shared = things.observe(multicast: true);
    final lengths = <int>[];
    var done = false;
    shared.stream().listen((s) => lengths.add(s.length), onDone: () {
      done = true;
    });

    await tester.pumpWidget(MaterialApp(
      home: QueryStreamBuilder<String>(
        query: shared,
        builder: (_, snaps) => Text('n:${snaps.length}'),
      ),
    ));
    expect(find.text('n:1'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    things.doc('two').create('b');
    await flush(tester);

    expect(done, isFalse);
    expect(lengths, [2]);
    shared.dispose();
  });

  testWidgets('removing a document builder keeps a caller-owned observer open',
      (tester) async {
    final things = Loon.collection<String>('things');
    things.doc('one').create('a', broadcast: false);
    final shared = things.doc('one').observe(multicast: true);
    final values = <String?>[];
    var done = false;
    shared.stream().listen((s) => values.add(s?.data), onDone: () {
      done = true;
    });

    await tester.pumpWidget(MaterialApp(
      home: DocumentStreamBuilder<String>(
        doc: shared,
        builder: (_, snap) => Text('v:${snap?.data}'),
      ),
    ));
    expect(find.text('v:a'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    things.doc('one').update('b');
    await flush(tester);

    expect(done, isFalse);
    expect(values, ['b']);
    shared.dispose();
  });

  testWidgets('builders sharing an observer keep it open for each other',
      (tester) async {
    final things = Loon.collection<String>('things');
    things.doc('one').create('a', broadcast: false);
    final shared = things.observe(multicast: true);
    Widget screen(bool showFirst) => MaterialApp(
          home: Column(children: [
            if (showFirst)
              QueryStreamBuilder<String>(
                key: const ValueKey('first'),
                query: shared,
                builder: (_, snaps) => Text('first:${snaps.length}'),
              ),
            QueryStreamBuilder<String>(
              key: const ValueKey('second'),
              query: shared,
              builder: (_, snaps) => Text('second:${snaps.length}'),
            ),
          ]),
        );

    await tester.pumpWidget(screen(true));
    expect(find.text('second:1'), findsOneWidget);
    await tester.pumpWidget(screen(false));
    things.doc('two').create('b');
    await flush(tester);

    expect(find.text('second:2'), findsOneWidget);
    shared.dispose();
  });

  testWidgets('switching sources keeps a caller-owned observer open',
      (tester) async {
    final things = Loon.collection<String>('things');
    things.doc('one').create('a', broadcast: false);
    things.doc('two').create('b', broadcast: false);
    final shared = things.doc('one').observe(multicast: true);
    final values = <String?>[];
    var done = false;
    shared.stream().listen((s) => values.add(s?.data), onDone: () {
      done = true;
    });
    Widget screen(DocumentView<String> doc) => MaterialApp(
          home: DocumentStreamBuilder<String>(
            doc: doc,
            builder: (_, snap) => Text('v:${snap?.data}'),
          ),
        );

    await tester.pumpWidget(screen(shared));
    await tester.pumpWidget(screen(things.doc('two')));
    await tester.pump();
    expect(find.text('v:b'), findsOneWidget);
    things.doc('one').update('c');
    await flush(tester);

    expect(done, isFalse);
    expect(values, ['c']);
    shared.dispose();
  });

  testWidgets('removing a builder keeps a caller-owned view observer open',
      (tester) async {
    animals.doc('rex').create(const TestDogModel('Rex'), broadcast: false);
    final shared = dogs.observe(multicast: true);
    final names = <List<String>>[];
    shared.stream().listen((s) => names.add(s.map((s) => s.data.name).toList()));

    await tester.pumpWidget(MaterialApp(
      home: QueryStreamBuilder<TestDogModel>(
        query: shared,
        builder: (_, snaps) => Text('n:${snaps.length}'),
      ),
    ));
    await tester.pumpWidget(const SizedBox.shrink());
    animals.doc('fido').create(const TestDogModel('Fido'));
    await flush(tester);

    expect(names, [
      ['Rex', 'Fido']
    ]);
    shared.dispose();
  });

  testWidgets('builder-created observers are released when removed or switched',
      (tester) async {
    animals.doc('one').create(const TestDogModel('Rex'), broadcast: false);
    Widget screen(
      DocumentView<TestAnimalModel> doc,
      Queryable<TestAnimalModel> query,
    ) =>
        MaterialApp(
          home: Column(children: [
            DocumentStreamBuilder(
              doc: doc,
              builder: (_, snap) => Text('doc:${snap?.data.name}'),
            ),
            QueryStreamBuilder(
              query: query,
              builder: (_, snaps) => Text('query:${snaps.length}'),
            ),
          ]),
        );

    await tester.pumpWidget(screen(dogs.doc('one'), dogs));
    await tester.pumpWidget(screen(animals.doc('one'), animals));
    await tester.pumpWidget(screen(dogs.doc('one'), dogs.where((_) => true)));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(Loon.inspect()['broadcastStore']['observerValues'], isEmpty);
  });
}
