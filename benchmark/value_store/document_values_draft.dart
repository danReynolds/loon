// Copied into the library only in disposable profiling variants.
import 'package:loon/loon.dart';

/// Reuses the last collection map during one synchronous operation.
/// Writes go through this helper. Call [invalidate] after external pruning.
class DocumentValues<T> {
  final ValueStore<T> _store;
  String? _parent;
  Map<String, T>? _values;

  DocumentValues(this._store);

  bool _select(Document doc) {
    // These constructor inputs do not split into the original parent and ID.
    if (doc.id.isEmpty || doc.id.contains('__') || doc.parent.endsWith('_')) {
      return false;
    }
    if (_parent != doc.parent) {
      _parent = doc.parent;
      _values = _store.getChildValues(doc.parent);
    }
    return true;
  }

  T? get(Document doc) =>
      _select(doc) ? (_values?[doc.id]) : _store.get(doc.path);

  void invalidate() {
    _parent = null;
    _values = null;
  }

  void write(Document doc, T value) {
    if (_select(doc) && _values != null) {
      _values![doc.id] = value;
    } else {
      _store.write(doc.path, value);
      // The write may create a collection map previously cached as absent.
      invalidate();
    }
  }
}
