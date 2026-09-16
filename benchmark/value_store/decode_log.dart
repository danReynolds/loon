import 'dart:convert';
import 'dart:io';
import 'package:args/args.dart';
import 'tool_support.dart';

Map<String, dynamic> decodeProfileLog(String log, {String? mode}) {
  List<String>? chunks;
  final results = <Map<String, dynamic>>[];
  for (final line in const LineSplitter().convert(log)) {
    if (line.contains('LOON_PROFILE_BEGIN')) {
      if (chunks != null) {
        throw const FormatException('Incomplete result before new frame');
      }
      chunks = [];
    } else if (line.contains('LOON_PROFILE_DATA:') && chunks != null) {
      chunks.add(line.split('LOON_PROFILE_DATA:')[1].trim());
    } else if (line.contains('LOON_PROFILE_END') && chunks != null) {
      results.add(jsonDecode(utf8.decode(base64.decode(chunks.join())))
          as Map<String, dynamic>);
      chunks = null;
    }
  }
  if (chunks != null || results.length != 1) {
    throw const FormatException('Expected exactly one complete result frame');
  }
  final data = results.single;
  if (data['exit_code'] != 0) {
    throw StateError('Benchmark failed: ${data['error']}');
  }
  if (mode != null && data['mode'] != mode) {
    throw StateError('Expected $mode, got ${data['mode']}');
  }
  return data;
}

void main(List<String> arguments) {
  final parser = ArgParser()
    ..addOption('out', mandatory: true)
    ..addOption('mode', allowed: ['jit', 'aot', 'profile']);
  final args = parser.parse(arguments);
  if (args.rest.length != 1) {
    throw ArgumentError(
        'Usage: dart run benchmark/value_store/decode_log.dart LOG --out FILE [--mode aot]');
  }
  final data = decodeProfileLog(File(args.rest.single).readAsStringSync(),
      mode: args['mode'] as String?);
  writeJson(args['out'] as String, data);
  stdout.writeln(args['out']);
}
