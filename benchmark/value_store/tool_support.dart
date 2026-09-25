import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const jsonFormat = JsonEncoder.withIndent('  ');

Map<String, dynamic> readJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void writeJson(String path, Object value) =>
    File(path).writeAsStringSync('${jsonFormat.convert(value)}\n');

String hashFile(String path) =>
    sha256.convert(File(path).readAsBytesSync()).toString();

String replaceOnce(String source, String old, String replacement) {
  if (old.allMatches(source).length != 1) {
    throw StateError('Update profiling transform for: $old');
  }
  return source.replaceFirst(old, replacement);
}

Future<String> commandOutput(List<String> command, {String? cwd}) async {
  final result = await Process.run(command.first, command.skip(1).toList(),
      workingDirectory: cwd);
  if (result.exitCode != 0) {
    throw ProcessException(command.first, command.skip(1).toList(),
        '${result.stderr}', result.exitCode);
  }
  return (result.stdout as String).trim();
}

double median(Iterable<num> values) {
  final sorted = values.toList()..sort();
  if (sorted.isEmpty) throw StateError('No samples');
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle].toDouble()
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

String milliseconds(num microseconds) =>
    (microseconds / 1000).toStringAsFixed(3);
