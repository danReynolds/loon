import 'dart:async';
import 'package:loon/persistor/file_persistor/file_data_store.dart';
import 'package:loon/persistor/file_persistor/file_persistor.dart';

class DebugFilePersistor extends FilePersistor {
  final _controller = StreamController<List<FileDataStore>>.broadcast();

  Stream<List<FileDataStore>> get stream {
    return _controller.stream;
  }

  @override
  persist(docs) async {
    await super.persist(docs);
    // _controller.add(getFileDataStores());
  }

  @override
  hydrate() async {
    final value = await super.hydrate();
    // _controller.add(getFileDataStores());
    return value;
  }
}
