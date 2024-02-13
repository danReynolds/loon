import 'dart:io';
import 'dart:isolate';
import 'package:loon/loon.dart';
import 'package:uuid/uuid.dart';

const uuid = Uuid();

abstract class TaskRequest<T extends TaskResponse> {
  final id = uuid.v4();

  TaskRequest();
}

abstract class TaskResponse {
  final String id;

  TaskResponse({
    required this.id,
  });
}

class InitTaskRequest extends TaskRequest<InitTaskResponse> {
  final SendPort sendPort;
  final PersistorSettings persistorSettings;
  final Directory directory;

  InitTaskRequest({
    required this.sendPort,
    required this.persistorSettings,
    required this.directory,
  });
}

class InitTaskResponse extends TaskResponse {
  final SendPort sendPort;

  InitTaskResponse({
    required super.id,
    required this.sendPort,
  });
}

class HydrateTaskRequest extends TaskRequest<HydrateTaskResponse> {}

class HydrateTaskResponse extends TaskResponse {
  final Map<String, Map<String, Json>> data;

  HydrateTaskResponse({
    required super.id,
    required this.data,
  });
}

class PersistTaskRequest extends TaskRequest<PersistTaskResponse> {
  final Map<Document, Json?> data;

  PersistTaskRequest({
    required this.data,
  });
}

class PersistTaskResponse extends TaskResponse {
  PersistTaskResponse({
    required super.id,
  });
}

class ClearTaskRequest extends TaskRequest<ClearTaskResponse> {}

class ClearTaskResponse extends TaskResponse {
  ClearTaskResponse({
    required super.id,
  });
}
