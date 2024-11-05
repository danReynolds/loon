import 'dart:js_interop';
import 'package:loon/persistor/data_store.dart';
import 'package:web/web.dart';

class IndexedDBDataStore extends DataStore {
  final IDBDatabase db;

  IndexedDBDataStore(
    super.name, {
    required this.db,
  });

  @override
  Future<void> delete() {
    // TODO: implement delete
    throw UnimplementedError();
  }

  @override
  Future<void> hydrate() {
    // TODO: implement hydrate
    throw UnimplementedError();
  }

  String get encryptedName {
    return "${name}_encrypted";
  }

  @override
  Future<void> persist() {
    final transaction = db.transaction([name.toJS, encryptedName.toJS].toJS);
    final plaintextObjectStore = transaction.objectStore(name);
    final encryptedObjectStore = transaction.objectStore(encryptedName);
  }
}
