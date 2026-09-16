import 'package:loon/loon.dart';

/// Experimental lazy counterpart to visitValues, with the same traversal order.
/// Traversal starts on iteration and repeats on every new iteration. This is a
/// live view, not a snapshot; do not structurally mutate the store mid-iteration.
Iterable<T> valuesUnder<T>(ValueStore<T> store, String path) sync* {
  Iterable<T> walk(Map? node) sync* {
    if (node == null) return;
    final Map? values = node['__values'];
    if (values != null) {
      yield* values.values.cast<T>();
    }
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
  final Map? values = parent?['__values'];
  if (values?.containsKey(last) ?? false) yield values![last] as T;
  yield* walk(parent?[last] as Map?);
}
