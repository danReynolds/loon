import 'package:loon/loon.dart';
import 'package:loon/persistor/file_persistor/file_persistor.dart';

import '../utils.dart';
import 'test_data_store_encrypter.dart';

class TestFilePersistor extends FilePersistor {
  static var completer = PersistorCompleter();

  TestFilePersistor({
    PersistorSettings? settings,
    void Function(Set<Document> batch)? onPersist,
    void Function(Set<Collection> collections)? onClear,
    void Function()? onClearAll,
    void Function(Json data)? onHydrate,
    void Function()? onSync,
  }) : super(
          // To make tests run faster, in the test environment the persistence throttle
          // is decreased to 1 millisecond.
          persistenceThrottle: const Duration(milliseconds: 1),
          settings: settings ?? const PersistorSettings(),
          encrypter: TestDataStoreEncrypter(),
          onPersist: (docs) {
            onPersist?.call(docs);
            completer.persistComplete();
          },
          onHydrate: (refs) {
            onHydrate?.call(refs);
            completer.hydrateComplete();
          },
          onClear: (collections) {
            onClear?.call(collections);
            completer.clearComplete();
          },
          onClearAll: () {
            onClearAll?.call();
            completer.clearAllComplete();
          },
          onSync: () {
            onSync?.call();
            completer.syncComplete();
          },
        );
}
