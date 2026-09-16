import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';

import 'package:loon/loon.dart';
import '../profile_support.dart';

/// Instrumented heap evidence, deliberately separate from release timings.
/// Uses VM class live counts/bytes after a requested GC, not process RSS.
Future<Map<String, Object?>> captureDependencyRetention(
    {int count = 100000}) async {
  check(profileMode != 'aot', 'Heap diagnosis requires profile or JIT mode');
  final info = await developer.Service.controlWebServer(
      enable: true, silenceOutput: true);
  final uri = info.serverWebSocketUri;
  check(uri != null, 'VM service unavailable');
  // Benchmark workflow is pinned to Dart 3.12.2; product SDK floor stays 3.0.
  // ignore: sdk_version_since
  final isolate = developer.Service.getIsolateId(Isolate.current)!;
  final socket = await WebSocket.connect('$uri');
  final pending = <String, Completer<Map<String, dynamic>>>{};
  var sequence = 0;
  final listener = socket.listen((event) {
    final json = jsonDecode(event as String) as Map<String, dynamic>;
    final response = pending.remove(json['id']);
    if (response == null) return;
    if (json['error'] != null) {
      response.completeError(StateError('${json['error']}'));
    } else {
      response.complete(json['result'] as Map<String, dynamic>);
    }
  });
  Future<Map<String, dynamic>> rpc(String method, Map<String, Object> params) {
    final id = '${sequence++}';
    final result = pending[id] = Completer<Map<String, dynamic>>();
    socket.add(jsonEncode(
        {'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params}));
    return result.future.timeout(const Duration(seconds: 30));
  }

  final captures = <Map<String, Object?>>[];
  Future<void> capture(String shape, String phase) async {
    // Let deletion broadcasts finish before counting reachable application data.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final profile =
        await rpc('getAllocationProfile', {'isolateId': isolate, 'gc': true});
    final classes = <String, Object>{};
    for (final raw in profile['members'] as List) {
      final stats = raw as Map;
      final name = (stats['class'] as Map)['name'] as String;
      if ({
        'Document',
        'DocumentSnapshot',
        '_DependencyEntry',
        'Collection',
        'PathPersistorSettings',
        '_Set',
        '_Map',
        '_OneByteString',
        '_TwoByteString'
      }.contains(name)) {
        classes[name] = {
          'instances_current': stats['instancesCurrent'],
          'bytes_current': stats['bytesCurrent'],
        };
      }
    }
    captures.add({
      'shape': shape,
      'phase': phase,
      'last_gc_date': profile['dateLastServiceGC'],
      'memory_usage': profile['memoryUsage'],
      'classes': classes,
    });
    final entryCount =
        ((classes['_DependencyEntry'] as Map?)?['instances_current'] as int?) ??
            0;
    if (phase == 'deleted' || phase == 'cleared') {
      check(entryCount == 0, 'Dependency entries released after $phase');
    }
  }

  try {
    for (final empty in [false, true]) {
      final shape = empty ? 'empty_dependencies' : 'one_shared_source';
      Loon.configure(persistor: null);
      Loon.unsubscribe();
      await Loon.clearAll(broadcast: false);
      await capture(shape, 'baseline');
      _seed(count, empty);
      await capture(shape, 'seeded');
      _replaceHandles(count, empty);
      await capture(shape, 'handles_replaced');
      Loon.collection('transactions').delete();
      await capture(shape, 'deleted');
      await Loon.clearAll(broadcast: false);
      await capture(shape, 'cleared');
    }
    return {
      'schema': 1,
      'mode': profileMode,
      'host': 'flutter_app',
      'suite': 'dependency_retention',
      'variant': profileSetting('PROFILE_VARIANT') ?? 'workspace',
      'documents': count,
      'captures': captures,
      'method':
          'VM getAllocationProfile(gc:true); live class shallow bytes and isolate heap usage. GC is requested, not guaranteed by the protocol.',
    };
  } finally {
    await listener.cancel();
    await socket.close();
  }
}

Collection<int> _transactions(bool empty) {
  final accounts = Loon.collection<int>('accounts');
  return Loon.collection<int>('transactions',
      dependenciesBuilder: (_) =>
          empty ? <Document>{} : {accounts.doc('alice')});
}

void _seed(int count, bool empty) {
  Loon.collection<int>('accounts')
      .doc('alice')
      .create(0, broadcast: false, persist: false);
  final transactions = _transactions(empty);
  for (var i = 0; i < count; i++) {
    transactions.doc('$i').create(0, broadcast: false, persist: false);
  }
}

void _replaceHandles(int count, bool empty) {
  final transactions = _transactions(empty);
  for (var i = 0; i < count; i++) {
    transactions.doc('$i').update(1, broadcast: false, persist: false);
  }
}
