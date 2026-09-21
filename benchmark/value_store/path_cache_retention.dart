import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';
import 'package:loon/loon.dart';
import 'path_cache_draft.dart';

// Copied by run_path_cache_retention.dart into the frozen standalone library.
// The collector runs in a different process so its allocations do not enter
// the measured VM heap. These diagnostic bytes are separate from release timing.
Future<void> main(List<String> args) async {
  if (args.contains('--worker')) return _worker();
  if (args.length != 1) throw ArgumentError('Expected output JSON path');
  final runs = <Map<String, Object?>>[];
  for (final shape in ['flat', 'deep']) {
    for (final mode in ['owned', 'lru_512k', 'lru_2m', 'recent']) {
      final process = await Process.start(Platform.resolvedExecutable, [
        '--enable-vm-service=0',
        '--no-dds',
        Platform.script.toFilePath(),
        '--worker'
      ]);
      final ready = Completer<Map<String, dynamic>>();
      final pending = <int, Completer<Map<String, dynamic>>>{};
      final errors = StringBuffer();
      final stdoutListener = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (!line.startsWith('PATH_HEAP:')) return;
        final data = jsonDecode(line.substring(10)) as Map<String, dynamic>;
        if (data['ready'] == true) {
          ready.complete(data);
        } else {
          pending.remove(data['id'])!.complete(data);
        }
      });
      final stderrListener =
          process.stderr.transform(utf8.decoder).listen(errors.write);
      unawaited(process.exitCode.then((code) {
        if (!ready.isCompleted) {
          ready.completeError(StateError('Worker exited $code: $errors'));
        }
      }));
      WebSocket? socket;
      StreamSubscription? socketListener;
      var stage = 'worker startup';
      try {
        final info = await ready.future.timeout(const Duration(seconds: 30));
        stage = 'VM service connection';
        socket = await WebSocket.connect(info['uri'] as String);
        final rpcPending = <String, Completer<Map<String, dynamic>>>{};
        var sequence = 0;
        socketListener = socket.listen((event) {
          final data = jsonDecode(event as String) as Map<String, dynamic>;
          final call = rpcPending.remove(data['id']);
          if (call == null) return;
          if (data['error'] != null) {
            call.completeError(StateError('${data['error']}'));
          } else {
            call.complete(data['result'] as Map<String, dynamic>);
          }
        });
        Future<Map<String, dynamic>> rpc(
            String method, Map<String, Object> params) {
          final id = '${sequence++}';
          final call = rpcPending[id] = Completer<Map<String, dynamic>>();
          socket!.add(jsonEncode({
            'jsonrpc': '2.0',
            'id': id,
            'method': method,
            'params': params
          }));
          return call.future.timeout(const Duration(seconds: 30));
        }

        Future<Map<String, dynamic>> command(String op) async {
          stage = 'worker command $op';
          final id = sequence++;
          final response = pending[id] = Completer<Map<String, dynamic>>();
          process.stdin.writeln(
              jsonEncode({'id': id, 'op': op, 'mode': mode, 'shape': shape}));
          await process.stdin.flush();
          return response.future.timeout(const Duration(seconds: 30));
        }

        await command('warmup');
        final captures = <Map<String, Object?>>[];
        for (final phase in [
          'empty',
          'seeded',
          'parsed',
          'store_deleted',
          'owners_released',
          'cache_cleared'
        ]) {
          final state = await command(phase);
          await Future<void>.delayed(const Duration(milliseconds: 30));
          stage = 'GC/profile $phase';
          final profile = await rpc('getAllocationProfile',
              {'isolateId': info['isolate'] as String, 'gc': true});
          final classes = <String, Object>{};
          for (final member in profile['members'] as List) {
            final name = member['class']['name'] as String;
            if ({
              'ParsedStorePath',
              'PathOwner',
              '_PathCacheEntry',
              'BoundedPathCache',
              'RecentPathCache',
              '_OneByteString',
              '_TwoByteString',
              '_ImmutableList',
              '_List',
              '_GrowableList',
              '_Map'
            }.contains(name)) {
              classes[name] = {
                'instances': member['instancesCurrent'],
                'bytes': member['bytesCurrent']
              };
            }
          }
          final plans = (classes['ParsedStorePath'] as Map?)?['instances'] ?? 0;
          if ((phase == 'cache_cleared' ||
                  (phase == 'owners_released' && mode == 'owned')) &&
              plans != 0) {
            throw StateError(
                'Unreleased parsed paths at $shape/$mode/$phase: $plans');
          }
          captures.add({
            'phase': phase,
            'state': state,
            'last_gc_date': profile['dateLastServiceGC'],
            'memory_usage': profile['memoryUsage'],
            'classes': classes
          });
        }
        runs.add({'shape': shape, 'mode': mode, 'captures': captures});
        stdout.writeln('$shape/$mode: captured and cleanup checked');
      } catch (error) {
        throw StateError('$shape/$mode during $stage: $error\n$errors');
      } finally {
        await socketListener?.cancel();
        await socket?.close();
        process.kill();
        await process.exitCode;
        await stdoutListener.cancel();
        await stderrListener.cancel();
      }
    }
  }
  File(args.single)
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
    'dart': Platform.version,
    'host': Platform.operatingSystemVersion,
    'documents': 100000,
    'runs': runs,
    'method':
        'Separate-process Dart JIT getAllocationProfile(gc:true), live shallow class bytes and heap usage. GC requested; no RSS or dominator-size claims. Owners model optional path metadata, not added Document fields.',
  }));
}

final _store = ValueStore<int>();
List<PathOwner> _owners = [];
PathPlanCache? _cache;
String _mode = 'owned';

void _seed(String shape, int count) {
  _store.clear();
  _owners = [
    for (var i = 0; i < count; i++)
      PathOwner(shape == 'flat'
          ? 'items__$i'
          : 'orgs__o__teams__t__accounts__a__items__$i')
  ];
  for (var i = 0; i < count; i++) {
    _store.write(_owners[i].path, i);
  }
}

void _populate() {
  var sum = 0;
  for (final owner in _owners) {
    for (var repeat = 0; repeat < 2; repeat++) {
      final parsed = _mode == 'owned'
          ? (owner.parsed ??= ParsedStorePath(owner.path))
          : _cache?.lookup(owner.path);
      sum += parsed == null
          ? _store.get(owner.path)!
          : parsed.read<int>(_store.inspect())!;
    }
  }
  if (sum != _owners.length * (_owners.length - 1)) {
    throw StateError('Read checksum');
  }
}

Future<void> _worker() async {
  final info = await developer.Service.controlWebServer(
      enable: true, silenceOutput: true);
  // ignore: sdk_version_since
  final isolate = developer.Service.getIsolateId(Isolate.current);
  stdout.writeln('PATH_HEAP:${jsonEncode({
        'ready': true,
        'uri': '${info.serverWebSocketUri}',
        'isolate': isolate
      })}');
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    final message = jsonDecode(line) as Map<String, dynamic>;
    final shape = message['shape'] as String;
    switch (message['op']) {
      case 'warmup':
        _mode = message['mode'] as String;
        _cache = switch (_mode) {
          'lru_512k' => BoundedPathCache(),
          'lru_2m' =>
            BoundedPathCache(maxBytes: 2 * 1024 * 1024, maxEntries: 4096),
          'recent' => RecentPathCache(),
          _ => null,
        };
        _seed(shape, 10000);
        _populate();
        _store.clear();
        _owners = [];
        _cache?.clear();
      case 'seeded':
        _seed(shape, 100000);
      case 'parsed':
        _populate();
      case 'store_deleted':
        _store.clear();
      case 'owners_released':
        _owners = [];
      case 'cache_cleared':
        _cache?.clear();
    }
    stdout.writeln('PATH_HEAP:${jsonEncode({
          'id': message['id'],
          'owners': _owners.length,
          'cache_entries': _cache?.length ?? 0,
          'accounted_bytes': _cache?.accountedBytes ?? 0
        })}');
  }
}
