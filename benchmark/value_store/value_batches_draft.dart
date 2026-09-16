import 'package:loon/loon.dart';

/// Experimental shared traversal: yield existing value buckets, not copies.
/// Only ValueStore is supported; ValueRefStore has additional node metadata.
Iterable<Iterable<T>> valueBatches<T>(ValueStore<T> store, String path) sync* {
  Iterable<Iterable<T>> walk(Map? node) sync* {
    if (node == null) return;
    final Map<String, T>? values = node['__values'];
    if (values != null) yield values.values;
    for (final entry in node.entries) {
      if (entry.key != '__values') yield* walk(entry.value as Map);
    }
  }

  final root = store.inspect();
  if (path.isEmpty) {
    yield* walk(root);
    return;
  }
  final segments = path.split('__');
  final last = segments.removeLast();
  Map? parent = root;
  for (final segment in segments) {
    parent = parent?[segment] as Map?;
    if (parent == null) return;
  }
  final Map<String, T>? values = parent?['__values'];
  if (values?.containsKey(last) ?? false) yield [values![last] as T];
  yield* walk(parent?[last] as Map?);
}

Iterable<T> valuesViaBatches<T>(ValueStore<T> store, String path) sync* {
  for (final batch in valueBatches(store, path)) {
    yield* batch;
  }
}

Set<T> extractViaBatches<T>(ValueStore<T> store, String path) {
  final result = <T>{};
  for (final batch in valueBatches(store, path)) {
    result.addAll(batch);
  }
  return result;
}
