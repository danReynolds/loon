part of 'loon.dart';

/// A collection narrowed by [Collection.whereType] to the documents whose data is [T].
///
/// The source collection owns the stored snapshots and their serialization. Reads keep the
/// source's snapshots whose data is a [T], and writes go through the source and only affect
/// documents of type [T].
class _NarrowedCollection<T> extends Collection<T> {
  final Collection<Object?> _source;

  _NarrowedCollection(
    this._source, {
    super.toJson,
    super.dependenciesBuilder,
  }) : super(
          _source.parent,
          _source.name,
          persistorSettings: _source.persistorSettings,
        );

  @override
  Collection<S> whereType<S extends T>() {
    return _NarrowedCollection<S>(
      _source,
      toJson: toJson,
      dependenciesBuilder: dependenciesBuilder,
    );
  }

  @override
  Document<T> doc([String? id]) {
    return _NarrowedDocument<T>(
      _source,
      id ?? generateSecureId(),
      toJson: toJson,
      dependenciesBuilder: dependenciesBuilder,
    );
  }

  // Handles come from the source rather than the stored snapshots, so that they read and
  // write with the source's serialization.
  @override
  List<DocumentSnapshot<T>> get() {
    return [
      for (final snap in _source.get())
        if (snap.data case final T data)
          DocumentSnapshot(doc: doc(snap.id), data: data),
    ];
  }

  @override
  bool exists() {
    return _source.get().any((snap) => snap.data is T);
  }

  /// Deletes only the documents of type [T].
  @override
  void delete() {
    for (final snap in get()) {
      snap.doc.delete();
    }
  }

  /// Replaces only the documents of type [T], and throws before writing if a replacement ID
  /// belongs to a document of another type.
  @override
  void replace(List<DocumentSnapshot<T>> snaps) {
    for (final snap in snaps) {
      if (_source.doc(snap.id).exists() && !doc(snap.id).exists()) {
        throw Exception('Cannot replace document ${snap.path} of another type');
      }
    }

    delete();
    for (final snap in snaps) {
      doc(snap.id).create(snap.data);
    }
  }
}

/// The reads and writes shared by narrowed documents and their observers.
mixin _NarrowedDocumentMixin<T> on Document<T> {
  Document<Object?> get _source;

  DocumentSnapshot<T>? _narrow() {
    final snap = _source.get();
    if (snap == null) {
      return null;
    }
    final data = snap.data;
    return data is T ? DocumentSnapshot(doc: this, data: data) : null;
  }

  @override
  bool exists() {
    return get() != null;
  }

  /// The source rejects an ID that is taken by a document of any type.
  @override
  DocumentSnapshot<T> create(
    T data, {
    bool broadcast = true,
    bool persist = true,
  }) {
    _source.create(data, broadcast: broadcast, persist: persist);
    return DocumentSnapshot(doc: this, data: data);
  }

  /// Only updates a document of type [T]. Changing a document's type is a write through the
  /// collection that owns it.
  @override
  DocumentSnapshot<T> update(
    T data, {
    bool? broadcast,
    bool persist = true,
  }) {
    if (!exists()) {
      throw Exception('Missing document $path');
    }
    _source.update(data, broadcast: broadcast, persist: persist);
    return DocumentSnapshot(doc: this, data: data);
  }

  /// Only deletes a document of type [T].
  @override
  void delete() {
    if (exists()) {
      _source.delete();
    }
  }

  @override
  void rebuildDependencies() {
    if (exists()) {
      _source.rebuildDependencies();
    }
  }
}

/// A document narrowed by [Collection.whereType]. It reads as absent while its data is not a [T].
class _NarrowedDocument<T> extends Document<T> with _NarrowedDocumentMixin<T> {
  final Collection<Object?> _collection;

  // Created on first use, since the documents of most narrowed snapshots are never read.
  @override
  late final Document<Object?> _source = _collection.doc(id);

  _NarrowedDocument(
    this._collection,
    String id, {
    super.toJson,
    super.dependenciesBuilder,
  }) : super(
          _collection.path,
          id,
          persistorSettings: _collection.persistorSettings,
        );

  @override
  DocumentSnapshot<T>? get() {
    return _narrow();
  }

  @override
  ObservableDocument<T> observe({
    bool multicast = false,
  }) {
    return _NarrowedObservableDocument<T>(
      _source,
      toJson: toJson,
      dependenciesBuilder: dependenciesBuilder,
      multicast: multicast,
    );
  }
}

/// Observes a narrowed document, reporting changes relative to its type: a document that
/// becomes a [T] is added, one that stops being a [T] is removed, and changes to other types
/// are skipped.
class _NarrowedObservableDocument<T> extends ObservableDocument<T>
    with _NarrowedDocumentMixin<T> {
  @override
  final Document<Object?> _source;

  _NarrowedObservableDocument(
    this._source, {
    super.toJson,
    super.dependenciesBuilder,
    required super.multicast,
  }) : super(
          _source.parent,
          _source.id,
          persistorSettings: _source.persistorSettings,
        );

  @override
  DocumentSnapshot<T>? _readSnapshot() {
    return _narrow();
  }

  @override
  BroadcastEvents? _changeEvent(
    BroadcastEvents event,
    DocumentSnapshot<T>? snap,
  ) {
    final prevSnap = _controllerValue;
    if (prevSnap == null && snap == null) {
      return null;
    }
    if (prevSnap == null) {
      return event == BroadcastEvents.hydrated ? event : BroadcastEvents.added;
    }
    if (snap == null) {
      return BroadcastEvents.removed;
    }
    return event;
  }
}
