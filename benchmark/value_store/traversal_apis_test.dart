import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';
import 'traversal_api_draft.dart';
import 'value_batches_draft.dart';
import 'visitor_draft.dart';
import 'workloads/traversal_apis.dart';

void main() {
  test(
      'manual iterator and bucket traversal preserve order, nulls and duplicates',
      () {
    final store = ValueStore<int?>();
    final lazy = manualValuesUnder(store, 'a');
    final iterator = lazy.iterator;
    store.write('', 9);
    store.write('a', 2);
    store.write('a__children__1', 2);
    store.write('a__children__2', null);
    store.write('other', 7);
    for (final path in ['', 'a', 'a__children', 'a__children__2', 'missing']) {
      final expected = <int?>[];
      visitValues(store, path, expected.add);
      expect(manualValuesUnder(store, path), orderedEquals(expected));
      expect(valueBatches(store, path).expand((bucket) => bucket),
          orderedEquals(expected));
      expect(exportSpecialized(store, path), orderedEquals(expected));
      final typed = <int?>[];
      visitTypedValues(store, path, typed.add);
      expect(typed, orderedEquals(expected));
    }
    expect(iterator.moveNext(), isTrue);
    expect(iterator.current, 2);
    final second = lazy.iterator;
    expect(second.moveNext(), isTrue);
    expect(second.current, 2);
    expect(iterator.moveNext(), isTrue);
    expect(iterator.current, 2);
    expect(iterator.moveNext(), isTrue);
    expect(iterator.current, isNull);
    expect(iterator.moveNext(), isFalse);
    expect(iterator.moveNext(), isFalse);
    var consumed = 0;
    expect(
        lazy.map((value) {
          consumed++;
          return value;
        }).take(1),
        [2]);
    expect(consumed, 1);
    store.clear();
    store.write('a', 5);
    expect(lazy, [5]);
    expect(iterator.moveNext(), isFalse);
  });

  test('manual iterator handles deep trees without recursive traversal calls',
      () {
    final store = ValueStore<int>();
    store.write(List.filled(4000, 'node').join('__'), 42);
    expect(manualValuesUnder(store, '').single, 42);
  });

  test(
      'all traversal APIs match an independent model through writes and deletes',
      () {
    for (var seed = 0; seed < 5; seed++) {
      final random = Random(seed);
      final store = ValueStore<int>();
      final model = <String, int>{};
      for (var step = 0; step < 100; step++) {
        final path =
            List.generate(random.nextInt(4) + 1, (_) => '${random.nextInt(4)}')
                .join('__');
        if (random.nextInt(4) == 0) {
          store.delete(path);
          model.removeWhere(
              (key, _) => key == path || key.startsWith('${path}__'));
        } else {
          final value = random.nextInt(10);
          store.write(path, value);
          model[path] = value;
        }
        for (final scope in ['', path, '0', 'missing']) {
          final values = model.entries
              .where((entry) =>
                  scope.isEmpty ||
                  entry.key == scope ||
                  entry.key.startsWith('${scope}__'))
              .map((entry) => entry.value)
              .toList();
          final expectedOrder = <int>[];
          visitValues(store, scope, expectedOrder.add);
          for (final api in TraversalApi.values) {
            final expectedValues =
                api == TraversalApi.extraction ? values.toSet() : values;
            expect(sumWithApi(api, store, scope),
                expectedValues.fold(0, (a, b) => a + b));
            final exported = exportWithApi(api, store, scope);
            expect(exported, unorderedEquals(expectedValues));
            expect(
                exported,
                orderedEquals(api == TraversalApi.extraction
                    ? expectedOrder.toSet()
                    : expectedOrder));
          }
        }
      }
    }
  });

  test(
      'specialized and generic cleanup include own entries, descendants and pruning',
      () {
    for (final api in TraversalApi.values) {
      final own = Document<int>('accounts', 'gone');
      final child = Document<int>('accounts__gone__transactions', '1');
      final survivor = Document<int>('accounts', 'kept');
      final a = Document<int>('sources', 'a');
      final b = Document<int>('sources', 'b');
      final forward = ValueStore<TraversalEntry>()
        ..write(own.path, TraversalEntry(own, {a}))
        ..write(child.path, TraversalEntry(child, {a, b}))
        ..write(survivor.path, TraversalEntry(survivor, {a}));
      final reverse = ValueStore<Set<Document>>()
        ..write(a.path, {own, child, survivor})
        ..write(b.path, {child});
      cleanupWithApi(api, forward, own.path, reverse);
      expect(forward.extract().keys, [survivor.path]);
      expect(reverse.extract(), {
        a.path: {survivor}
      });
    }
  });

  test('all union implementations preserve membership across overlapping sets',
      () {
    final a = Document<int>('tx', 'a');
    final b = Document<int>('tx', 'b');
    final c = Document<int>('tx', 'c');
    final store = ValueStore<Set<Document>>()
      ..write('accounts', {a})
      ..write('accounts__1', {a, b})
      ..write('accounts__2__nested', {b, c});
    for (final api in TraversalApi.values) {
      expect(unionWithApi(api, store, 'accounts'), {a, b, c});
      expect(unionWithApi(api, store, 'missing'), isEmpty);
    }
  });

  test('callback, generator, iterator, buckets and specialized operations',
      profileTraversalApis);
}
