import 'dart:async';

import '../loon.dart';

class DebugFilePersistor extends FilePersistor {
  final _controller = StreamController<List<FileDataStore>>.broadcast();

  Stream<List<FileDataStore>> get stream {
    return _controller.stream;
  }

  @override
  persist(List<BroadcastDocument> docs) async {
    await super.persist(docs);
    _controller.add(getFileDataStores());
  }

  @override
  hydrate() async {
    final value = await super.hydrate();
    _controller.add(getFileDataStores());
    return value;
  }

  @override
  clear(String collection) async {
    await super.clear(collection);
    _controller.add(getFileDataStores());
  }
}
