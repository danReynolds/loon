import 'dart:io';
import 'package:path/path.dart' as p;
import 'tool_support.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    throw ArgumentError('Expected a frozen run_core candidate directory');
  }
  final directory = p.absolute(args.single);
  final output = p.join(directory, 'retention.json');
  if (File(output).existsSync()) throw StateError('Output exists');
  final source = File(p.join(
      File.fromUri(Platform.script).parent.path, 'path_cache_retention.dart'));
  final target = File(p.join(directory, 'retention.dart'));
  target.writeAsStringSync(source
      .readAsStringSync()
      .replaceFirst("'package:loon/loon.dart'", "'store.dart'"));
  final result =
      await Process.run(Platform.resolvedExecutable, [target.path, output]);
  File(p.join(directory, 'retention.log'))
      .writeAsStringSync('${result.stdout}${result.stderr}');
  if (result.exitCode != 0) {
    throw StateError('${result.stdout}${result.stderr}');
  }
  writeJson(p.join(directory, 'retention-receipt.json'), {
    'command': [Platform.resolvedExecutable, target.path, output],
    'exit_code': result.exitCode,
    'collector_sha256': hashFile(source.path),
    'draft_sha256': hashFile(p.join(directory, 'path_cache_draft.dart')),
    'store_sha256': hashFile(p.join(directory, 'store.dart')),
  });
  stdout.write(result.stdout);
}
