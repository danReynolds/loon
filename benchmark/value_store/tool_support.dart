import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

const jsonFormat = JsonEncoder.withIndent('  ');

Map<String, dynamic> readJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void writeJson(String path, Object value) =>
    File(path).writeAsStringSync('${jsonFormat.convert(value)}\n');

String hashFile(String path) =>
    sha256.convert(File(path).readAsBytesSync()).toString();

List<File> filesUnder(String directory) => Directory(directory)
    .listSync(recursive: true, followLinks: false)
    .whereType<File>()
    .toList()
  ..sort((a, b) => a.path.compareTo(b.path));

Map<String, String> sourceHashes(String directory, String relativeTo) => {
      for (final file in filesUnder(directory))
        if (file.path.endsWith('.dart'))
          p.relative(file.path, from: relativeTo): hashFile(file.path),
    };

void copyTree(String source, String destination) {
  Directory(destination).createSync(recursive: true);
  for (final entry in Directory(source).listSync(followLinks: false)) {
    if ({'results', '__pycache__'}.contains(p.basename(entry.path))) continue;
    final target = p.join(destination, p.basename(entry.path));
    if (entry is Directory) {
      copyTree(entry.path, target);
    } else if (entry is File) {
      entry.copySync(target);
    }
  }
}

// pub's generated lockfile has a stable indentation/layout. Only hosted package
// versions are copied into overrides; path and SDK dependencies remain intact.
Map<String, String> lockedVersions(String path) {
  final blocks = RegExp(r'^  (\w+):\n(.*?)(?=^  \w+:|^sdks:|$(?![\s\S]))',
          multiLine: true, dotAll: true)
      .allMatches(File(path).readAsStringSync());
  return {
    for (final block in blocks)
      if (block[2]!.contains('    source: hosted'))
        block[1]!: RegExp(r'^    version: "([^"]+)"', multiLine: true)
            .firstMatch(block[2]!)!
            .group(1)!,
  };
}

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
