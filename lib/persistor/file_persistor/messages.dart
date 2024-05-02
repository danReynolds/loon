import 'dart:io';
import 'dart:isolate';
import 'package:encrypt/encrypt.dart';
import 'package:loon/loon.dart';
import 'package:loon/persistor/file_persistor/file_persist_document.dart';
import 'package:uuid/uuid.dart';

const uuid = Uuid();

abstract class MessageRequest<T extends MessageResponse> {
  final id = uuid.v4();

  MessageRequest();

  ErrorMessageResponse error(String text) {
    return ErrorMessageResponse(id: id, text: text);
  }
}

abstract class MessageResponse {
  final String id;

  MessageResponse({
    required this.id,
  });
}

class InitMessageRequest extends MessageRequest<InitMessageResponse> {
  final SendPort sendPort;
  final Directory directory;
  final Encrypter? encrypter;

  InitMessageRequest({
    required this.sendPort,
    required this.directory,
    required this.encrypter,
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

  HydrateMessageResponse success(Map<String, Json> data) {
    return HydrateMessageResponse(
      id: id,
      data: data,
    );
  }
}

class HydrateMessageResponse extends MessageResponse {
  /// A map of document paths to the document's hydrated data.
  final Map<String, Json> data;

  HydrateMessageResponse({
    required super.id,
    required this.data,
  });
}

class PersistMessageRequest extends MessageRequest<PersistMessageResponse> {
  final List<FilePersistDocument> data;

  PersistMessageRequest({
    required this.data,
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
  final String path;

  ClearMessageRequest({
    required this.path,
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

class LogMessageResponse extends MessageResponse {
  final String text;

  LogMessageResponse({
    required this.text,
  }) : super(id: '');
}
