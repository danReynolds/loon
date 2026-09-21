import 'package:loon/loon.dart';

/// Reads the last collection map without repeatedly traversing its path.
/// Keep this within one synchronous operation and invalidate after pruning.
class CollectionValues<T> {
  final ValueStore<T> _store;
  String? _path;
  Map<String, T>? _values;

  CollectionValues(this._store);

  Map<String, T>? operator [](String path) {
    if (_path != path) {
      _path = path;
      _values = _store.getChildValues(path);
    }
    return _values;
  }

  void invalidate() {
    _path = null;
    _values = null;
  }
}

// Other constructor inputs need full-path lookup to preserve segment boundaries.
bool canUseDocumentCollection(Document doc) =>
    doc.id.isNotEmpty && !doc.id.contains('__') && !doc.parent.endsWith('_');
