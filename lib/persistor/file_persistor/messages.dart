import 'dart:io';
import 'dart:isolate';
import 'package:loon/loon.dart';
import 'package:uuid/uuid.dart';

const uuid = Uuid();

abstract class MessageRequest<T extends MessageResponse> {
  final id = uuid.v4();

  MessageRequest();
}

abstract class MessageResponse {
  final String id;

  MessageResponse({
    required this.id,
  });
}

class InitMessageRequest extends MessageRequest<InitMessageResponse> {
  final SendPort sendPort;
  final PersistorSettings persistorSettings;
  final Directory directory;

  InitMessageRequest({
    required this.sendPort,
    required this.persistorSettings,
    required this.directory,
  });
}

class InitMessageResponse extends MessageResponse {
  final SendPort sendPort;

  InitMessageResponse({
    required super.id,
    required this.sendPort,
  });
}

class HydrateMessageRequest extends MessageRequest<HydrateMessageResponse> {}

class HydrateMessageResponse extends MessageResponse {
  final Map<String, Map<String, Json>> data;

  HydrateMessageResponse({
    required super.id,
    required this.data,
  });
}

class PersistMessageRequest extends MessageRequest<PersistMessageResponse> {
  final Map<Document, Json?> data;

  PersistMessageRequest({
    required this.data,
  });
}

class PersistMessageResponse extends MessageResponse {
  PersistMessageResponse({
    required super.id,
  });
}

class ClearMessageRequest extends MessageRequest<ClearMessageResponse> {}

class ClearMessageResponse extends MessageResponse {
  ClearMessageResponse({
    required super.id,
  });
}
