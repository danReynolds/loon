// Only used by run_core.dart's manager_core isolation experiment. These handles
// reproduce the fields, equality and lazy path/hash used by the hot algorithms;
// they omit persistence, data storage, snapshot reads and real observers.
// Correctness still requires tests against the actual Loon library.
const managerFixtures = r'''

abstract class StoreReference {
  String get path;
}

class Document<T> implements StoreReference {
  final String parent;
  final String id;
  final Set<Document>? Function(DocumentSnapshot<T>)? dependenciesBuilder;

  Document(this.parent, this.id, {this.dependenciesBuilder});

  @override
  late final String path = id.isEmpty ? parent : '${parent}__$id';
  @override
  late final int hashCode = Object.hash(parent, id);
  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Document && other.path == path;
}

class Collection implements StoreReference {
  @override
  final String path;
  Collection(this.path);
}

class BroadcastObserver<T, S> {
  String get path => throw UnsupportedError('No observers in this fixture');
  String get _observerId => path;
  void _onBroadcast() => throw UnsupportedError('No observers in this fixture');
  void dispose() => throw UnsupportedError('No observers in this fixture');
}

class Loon {
  static final _instance = Loon();
  final dependencyManager = DependencyManager();
  static DependencyManager get dependencies => _instance.dependencyManager;
}

// Same set comparison as Flutter foundation's collections.dart.
bool setEquals<T>(Set<T>? a, Set<T>? b) {
  if (a == null) return b == null;
  if (b == null || a.length != b.length) return false;
  if (identical(a, b)) return true;
  for (final value in a) {
    if (!b.contains(value)) return false;
  }
  return true;
}
''';
