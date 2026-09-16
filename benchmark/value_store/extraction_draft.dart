import 'dart:collection';
import 'package:loon/loon.dart';

// Experiments only. All ordered candidates preserve the current set snapshot,
// first-seen order, equality semantics, nulls and target-own-value behavior.
Set<T> extractForEach<T>(ValueStore<T> store, String path) =>
    _extractInto(store, path, <T>{}, _collectForEach<T>);

Set<T> extractDirectLoop<T>(ValueStore<T> store, String path) =>
    _extractInto(store, path, <T>{}, _collectDirectLoop<T>);

// Changes iteration order. A diagnostic, not a drop-in candidate.
Set<T> extractUnordered<T>(ValueStore<T> store, String path) =>
    _extractInto(store, path, HashSet<T>(), _collectForEach<T>);

Set<T> _extractInto<T>(ValueStore<T> store, String path, Set<T> result,
    void Function(Map, Set<T>) collect) {
  final root = store.inspect();
  if (path.isEmpty) {
    collect(root, result);
    return result;
  }
  final segments = path.split('__');
  final last = segments.removeLast();
  Map? parent = root;
  for (final segment in segments) {
    parent = parent?[segment] as Map?;
    if (parent == null) return result;
  }
  final Map? values = parent?['__values'];
  if (values?.containsKey(last) ?? false) result.add(values![last] as T);
  final Map? child = parent?[last];
  if (child != null) collect(child, result);
  return result;
}

void _collectForEach<T>(Map node, Set<T> result) {
  final Map<String, T>? values = node['__values'];
  if (values != null) {
    result.addAll(values.values);
    if (node.length == 1) return;
  }
  node.forEach((key, child) {
    if (key != '__values') _collectForEach(child as Map, result);
  });
}

void _collectDirectLoop<T>(Map node, Set<T> result) {
  final Map<String, T>? values = node['__values'];
  if (values != null) {
    for (final value in values.values) {
      result.add(value);
    }
    if (node.length == 1) return;
  }
  for (final entry in node.entries) {
    if (entry.key != '__values') _collectDirectLoop(entry.value as Map, result);
  }
}
