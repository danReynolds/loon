import 'dart:io';
import 'package:path/path.dart' as p;
import 'tool_support.dart';

/// Run separately built profile hosts. No heap measurements enter timing tables.
Future<void> main(List<String> args) async {
  if (args.length != 1) {
    throw ArgumentError(
        'Usage: dart run benchmark/value_store/run_retention.dart BUILD_DIRECTORY');
  }
  final root = p.absolute(args.single);
  final manifest = readJson(p.join(root, 'manifest.json'));
  final variants = (manifest['variants'] as List).cast<String>();
  final runs = <String, Object>{};
  for (var pass = 1; pass <= 3; pass++) {
    for (final variant in pass.isOdd ? variants : variants.reversed) {
      final app =
          (manifest['artifacts'] as Map)['$variant/profile']['app'] as String;
      final name = 'retention-$pass-$variant';
      final output = p.join(root, '$name.json');
      if (File(output).existsSync()) {
        throw StateError('Existing output: $output');
      }
      final watch = Stopwatch()..start();
      final result = await Process.run(
          p.join(app, 'Contents/MacOS/loon_profile'), [],
          environment: {
            ...Platform.environment,
            'PROFILE_SUITE': 'dependency_retention',
            'PROFILE_VARIANT': variant,
            'PROFILE_EXPECT_MODE': 'profile',
            'PROFILE_EXIT': 'true',
            'PROFILE_OUTPUT': output,
          });
      File(p.join(root, '$name.log'))
          .writeAsStringSync('${result.stdout}\n${result.stderr}');
      if (result.exitCode != 0 || !File(output).existsSync()) {
        stderr.writeln(result.stderr);
        throw StateError('Failed $name; see log');
      }
      final data = readJson(output);
      if (data['exit_code'] != 0 ||
          data['mode'] != 'profile' ||
          data['variant'] != variant) {
        throw StateError('Invalid heap result: $output');
      }
      runs[name] = data;
      stdout.writeln(
          '$name: ${watch.elapsedMilliseconds} ms; ${data['captures'].length} heap samples');
    }
  }
  writeJson(p.join(root, 'retention-results.json'), {
    'manifest': manifest,
    'runs': runs,
    'collector_sha256': hashFile(File.fromUri(Platform.script).path),
  });
}
