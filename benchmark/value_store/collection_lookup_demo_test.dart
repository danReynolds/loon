import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';

/// Demonstrates the proposed internal broadcast traversal with existing APIs.
/// Input handles use ordinary, nonempty IDs without the path delimiter.
/// The returned documents would have their observer caches invalidated before
/// the outer broadcast operation schedules delivery. No stores may be deleted
/// during this traversal; the maps are retained only until this call returns.
List<Document> queueDependentTouches(
  Document source,
  ValueStore<Set<Document>> reverse,
  ValueStore<BroadcastEvents> events,
) {
  final reverseByCollection = <String, Map<String, Set<Document>>?>{};
  final eventsByCollection = <String, Map<String, BroadcastEvents>>{};
  final touched = <Document>[];

  Set<Document>? dependentsOf(Document doc) {
    final children = reverseByCollection.putIfAbsent(
        doc.parent, () => reverse.getChildValues(doc.parent));
    return children?[doc.id];
  }

  bool queueTouch(Document doc) {
    final bucket =
        eventsByCollection[doc.parent] ?? events.getChildValues(doc.parent);
    if (bucket == null) {
      // Only the first event in a previously empty collection needs a path write.
      events.write(doc.path, BroadcastEvents.touched);
      eventsByCollection[doc.parent] = events.getChildValues(doc.parent)!;
      return true;
    }
    eventsByCollection[doc.parent] = bucket;
    if (bucket.containsKey(doc.id)) return false;
    bucket[doc.id] = BroadcastEvents.touched;
    return true;
  }

  void visit(Document doc) {
    for (final dependent in dependentsOf(doc) ?? <Document>{}) {
      if (queueTouch(dependent)) {
        touched.add(dependent);
        visit(dependent);
      }
    }
  }

  visit(source);
  return touched;
}

void main() {
  test('an account update queues transactions and downstream summaries once',
      () {
    final account = Document<int>('accounts', 'checking');
    final first = Document<int>('transactions', 't1');
    final second = Document<int>('transactions', 't2');
    final summary = Document<int>('summaries', 'monthly');
    final reverse = ValueStore<Set<Document>>()
      ..write(account.path, {first, second})
      ..write(first.path, {summary})
      ..write(second.path, {summary})
      ..write(summary.path, {account}); // A cycle back to the source.
    final events = ValueStore<BroadcastEvents>()
      ..write(account.path, BroadcastEvents.modified);

    expect(queueDependentTouches(account, reverse, events),
        [first, summary, second]);
    expect(events.get(account.path), BroadcastEvents.modified);
    expect(events.get(first.path), BroadcastEvents.touched);
    expect(events.get(second.path), BroadcastEvents.touched);
    expect(queueDependentTouches(account, reverse, events), isEmpty);

    // A subsequent call resolves fresh maps after the stores have been cleared.
    events.clear();
    events.write(account.path, BroadcastEvents.modified);
    expect(queueDependentTouches(account, reverse, events).length, 3);
  });
}
