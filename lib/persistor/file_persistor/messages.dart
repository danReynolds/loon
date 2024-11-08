import 'dart:io';
import 'dart:isolate';
import 'package:loon/loon.dart';
import 'package:loon/persistor/data_store_encrypter.dart';
import 'package:loon/persistor/data_store_persistence_payload.dart';
import 'package:uuid/uuid.dart';

const uuid = Uuid();

abstract class Message {}

abstract class MessageRequest<T extends MessageResponse> extends Message {
  final id = uuid.v4();

  MessageRequest();

  ErrorMessageResponse error(String text) {
    return ErrorMessageResponse(id: id, text: text);
  }
}

abstract class MessageResponse extends Message {
  final String id;

  MessageResponse({
    required this.id,
  });
}

class InitMessageRequest extends MessageRequest<InitMessageResponse> {
  final SendPort sendPort;
  final Directory directory;
  final DataStoreEncrypter encrypter;
  final Duration persistenceThrottle;
  final PersistorSettings settings;

  InitMessageRequest({
    required this.sendPort,
    required this.directory,
    required this.encrypter,
    required this.persistenceThrottle,
    required this.settings,
  });

  InitMessageResponse success(SendPort sendPort) {
    return InitMessageResponse(id: id, sendPort: sendPort);
  }
}

class InitMessageResponse extends MessageResponse {
  final SendPort sendPort;

  InitMessageResponse({
    required super.id,
    required this.sendPort,
  });
}

class HydrateMessageRequest extends MessageRequest<HydrateMessageResponse> {
  final List<String>? paths;

  HydrateMessageRequest([this.paths]);

  HydrateMessageResponse success(Map<String, dynamic> data) {
    return HydrateMessageResponse(
      id: id,
      data: data,
    );
  }
}

class HydrateMessageResponse extends MessageResponse {
  /// A map of document paths to the document's hydrated data.
  final Map<String, dynamic> data;

  HydrateMessageResponse({
    required super.id,
    required this.data,
  });
}

class PersistMessageRequest extends MessageRequest<PersistMessageResponse> {
  final DataStorePersistencePayload payload;

  PersistMessageRequest({
    required this.payload,
  });

  PersistMessageResponse success() {
    return PersistMessageResponse(id: id);
  }
}

class PersistMessageResponse extends MessageResponse {
  PersistMessageResponse({
    required super.id,
  });
}

class ClearMessageRequest extends MessageRequest<ClearMessageResponse> {
  final List<String> paths;

  ClearMessageRequest({
    required this.paths,
  });

  ClearMessageResponse success() {
    return ClearMessageResponse(id: id);
  }
}

class ClearMessageResponse extends MessageResponse {
  ClearMessageResponse({
    required super.id,
  });
}

class ClearAllMessageRequest extends MessageRequest<ClearAllMessageResponse> {
  ClearAllMessageResponse success() {
    return ClearAllMessageResponse(id: id);
  }
}

class ClearAllMessageResponse extends MessageResponse {
  ClearAllMessageResponse({
    required super.id,
  });
}

class ErrorMessageResponse extends MessageResponse {
  final String text;

  ErrorMessageResponse({
    required super.id,
    required this.text,
  });
}

class LogMessage extends Message {
  final String text;

  LogMessage({
    required this.text,
  });
}

class SyncCompleteMessage extends Message {}
