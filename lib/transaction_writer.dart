part of './loon.dart';

/// A helper for writing multiple document changes together or rolling them all back if needed.
class TransactionWriter {
  final Map<Document, dynamic> _rollbackIndex = {};
  bool _isCanceled = false;

  void _recordWrite(Document doc) {
    if (_isCanceled) {
      throw 'Cannot write a transaction after a rollback';
    }
    _rollbackIndex[doc] ??= doc.get()?.data;
  }

  DocumentSnapshot<T> create<T>(
    Document<T> doc,
    T data, {
    bool broadcast = true,
    bool persist = true,
  }) {
    _recordWrite(doc);
    return doc.create(data, broadcast: broadcast, persist: persist);
  }

  DocumentSnapshot<T> update<T>(
    Document<T> doc,
    T data, {
    bool? broadcast,
    bool persist = true,
  }) {
    _recordWrite(doc);
    return doc.update(data, broadcast: broadcast, persist: persist);
  }

  DocumentSnapshot<T>? modify<T>(
    Document<T> doc,
    ModifyFn<T> modifyFn, {
    bool? broadcast,
    bool persist = true,
  }) {
    _recordWrite(doc);
    return doc.modify(modifyFn, broadcast: broadcast, persist: persist);
  }

  DocumentSnapshot<T> createOrUpdate<T>(
    Document<T> doc,
    T data, {
    bool broadcast = true,
    bool persist = true,
  }) {
    _recordWrite(doc);
    return doc.createOrUpdate(data, broadcast: broadcast, persist: persist);
  }

  void delete<T>(Document<T> doc) {
    _recordWrite(doc);
    doc.delete();
  }

  void rollback() {
    if (_isCanceled) {
      return;
    }

    _isCanceled = true;

    for (final entry in _rollbackIndex.entries) {
      final doc = entry.key;
      final data = entry.value;

      if (data == null) {
        doc.delete();
      } else {
        doc.createOrUpdate(data);
      }
    }
  }
}
