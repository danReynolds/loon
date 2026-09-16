import 'package:loon/loon.dart';

/// Experimental traversal of ValueStore's current tree representation.
/// Uses inspect only to avoid adding a production API for this experiment.
/// Visits every stored value, including nulls and duplicates, at/below [path].
/// The callback must not structurally mutate this store while it is traversed.
void visitValues<T>(ValueStore<T> store, String path, void Function(T) visit) {
  void walk(Map? node) {
    if (node == null) return;
    final Map? values = node['__values'];
    if (values != null) {
      for (final value in values.values) {
        visit(value as T);
      }
    }
    for (final entry in node.entries) {
      if (entry.key != '__values') walk(entry.value as Map);
    }
  }

  final root = store.inspect();
  if (path.isEmpty) {
    walk(root);
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
  if (values?.containsKey(last) ?? false) visit(values![last] as T);
  walk(parent?[last] as Map?);
}
