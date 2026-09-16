import 'package:fake_async/fake_async.dart';
import 'package:loon/loon.dart';
import '../profile_support.dart';

void flush(FakeAsync async) {
  async.elapse(const Duration(milliseconds: 1));
  async.flushMicrotasks();
}

void profileDependencies() {
  final results = ProfileResults();
  for (final spec in [
    (name: '100k_shared', n: 100000, groups: 1, queries: 0),
    (name: '10k_four_queries', n: 10000, groups: 1, queries: 4),
    (name: '100k_100_groups', n: 100000, groups: 100, queries: 0),
    (name: '20k_nested', n: 20000, groups: 1, queries: 0),
  ]) {
    final selected = profileSetting('PROFILE_CASE');
    if (selected != null && selected != spec.name) continue;
    final samples = <String, List<int>>{
      for (final key in [
        'seed',
        'write',
        'delivery',
        'total',
        'ten_writes',
        'delete'
      ])
        key: [],
    };
    for (final recordSample in samplePhases()) {
      fakeAsync((async) {
        Loon.configure(persistor: null);
        Loon.unsubscribe();
        Loon.clearAll(broadcast: false);
        final accounts = Loon.collection<int>('accounts');
        for (var i = 0; i < spec.groups; i++) {
          accounts.doc('$i').create(0, broadcast: false, persist: false);
        }
        Set<Document> dependencies(DocumentSnapshot<int> snap) =>
            {accounts.doc('${snap.data % spec.groups}')};
        final transactions = spec.name == '20k_nested'
            ? Loon.collection('users').doc('alice').subcollection<int>(
                'transactions',
                dependenciesBuilder: dependencies)
            : Loon.collection<int>('transactions',
                dependenciesBuilder: dependencies);
        final watch = Stopwatch();
        int timed(void Function() action) {
          watch.reset();
          watch.start();
          action();
          watch.stop();
          return watch.elapsedMicroseconds;
        }

        final measured = <String, int>{};
        measured['seed'] = timed(() {
          for (var i = 0; i < spec.n; i++) {
            transactions.doc('$i').create(i, broadcast: false, persist: false);
          }
        });
        final observers = <ObservableQuery<int>>[];
        var deliveries = 0;
        for (var i = 0; i < spec.queries; i++) {
          final query = transactions
              .where((snap) => snap.data >= 0)
              .observe(multicast: true);
          query.stream().listen((_) {
            deliveries++;
          });
          observers.add(query);
        }
        flush(async);
        deliveries = 0;
        final source = accounts.doc('0');
        measured['write'] = timed(() {
          source.update(1, persist: false);
        });
        measured['delivery'] = timed(() {
          flush(async);
        });
        measured['total'] = measured['write']! + measured['delivery']!;
        check(deliveries == spec.queries, 'Query delivery count');
        deliveries = 0;
        measured['ten_writes'] = timed(() {
          for (var i = 2; i < 12; i++) {
            source.update(i, persist: false);
          }
        });
        flush(async);
        check(deliveries == spec.queries, 'Query delivery count');
        measured['delete'] = timed(transactions.delete);
        check((Loon.inspect()['dependentsStore'] as Map).isEmpty,
            'Reverse index cleanup');
        check((Loon.inspect()['dependencyStore'] as Map).isEmpty,
            'Forward index cleanup');
        flush(async);
        for (final observer in observers) {
          observer.dispose();
        }
        Loon.unsubscribe();
        Loon.clearAll(broadcast: false);
        if (recordSample) {
          measured.forEach((key, value) => samples[key]!.add(value));
        }
      });
    }
    samples.forEach((key, values) => results.add('${spec.name}/$key', values, {
          'documents': spec.n,
          'affected': spec.n ~/ spec.groups,
          'queries': spec.queries
        }));
  }
  results.save();
}
