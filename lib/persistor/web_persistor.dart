import 'package:loon/loon.dart';
import 'package:loon/persistor/indexed_db_persistor/indexed_db_persistor.dart';

class PersistorExtensions {
  static Persistor adaptive({
    void Function(Set<Document> batch)? onPersist,
    void Function(Set<Collection> collections)? onClear,
    void Function()? onClearAll,
    void Function(Json data)? onHydrate,
    void Function()? onSync,
    Duration persistenceThrottle = const Duration(milliseconds: 100),
    PersistorSettings settings = const PersistorSettings(),
  }) {
    return IndexedDBPersistor(
      onPersist: onPersist,
      onClear: onClear,
      onClearAll: onClearAll,
      onHydrate: onHydrate,
      onSync: onSync,
      persistenceThrottle: persistenceThrottle,
      settings: settings,
    );
  }
}
