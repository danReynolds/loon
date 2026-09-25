import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import 'manager_fixtures.dart';
import 'summarize.dart';
import 'tool_support.dart';
import 'workloads/manager_core.dart';

/// Compiles each candidate's actual store sources into a standalone program, away from Flutter
/// startup and build costs. Only their `part of` directives change; the Json alias matches
/// lib/src/json.dart. Candidates must also pass the full library's tests. The manager_core suite
/// substitutes explicit document/observer fixtures around the unchanged manager methods to screen
/// algorithm changes.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addMultiOption('source',
        splitCommas: false,
        help:
            'NAME=git:REF or NAME=dir:PACKAGE_ROOT; repeat for each candidate')
    ..addOption('out')
    ..addOption('modes', defaultsTo: 'jit,aot')
    ..addOption('suite',
        defaultsTo: 'store_core', allowed: ['store_core', 'manager_core'])
    ..addOption('filter',
        help:
            'Regular expression selecting store_core or manager_core operations')
    ..addOption('passes', defaultsTo: '3')
    ..addOption('trials', defaultsTo: '11')
    ..addOption('warmups', defaultsTo: '5')
    ..addOption('warmup-ms', defaultsTo: '200')
    ..addFlag('help', abbr: 'h', negatable: false);
  final args = parser.parse(arguments);
  if (args['help'] as bool) {
    stdout.writeln(parser.usage);
    return;
  }
  if (args.rest.isNotEmpty) throw ArgumentError('Unexpected arguments');
  int count(String name, [int minimum = 1]) {
    final result = int.parse(args[name] as String);
    if (result < minimum) throw ArgumentError('$name must be >= $minimum');
    return result;
  }

  final passes = count('passes');
  final trials = count('trials');
  final warmups = count('warmups');
  final warmupMs = count('warmup-ms', 0);
  final suite = args['suite'] as String;
  final filter = args['filter'] as String?;
  if (filter != null) RegExp(filter);
  final entrypoint =
      suite == 'manager_core' ? 'profileManagerCore' : 'profileStoreCore';
  final modes = (args['modes'] as String).split(',');
  if (modes.isEmpty ||
      modes.toSet().length != modes.length ||
      modes.any((mode) => !['jit', 'aot'].contains(mode))) {
    throw ArgumentError('Modes must be jit and/or aot');
  }
  final repo = File.fromUri(Platform.script).parent.parent.parent.path;
  final selections = List<String>.of(args['source'] as List<String>);
  if (selections.isEmpty) {
    selections
        .addAll(['main=git:origin/main', 'pr=git:HEAD', 'workspace=dir:$repo']);
  }
  final sources = <String, String>{};
  for (final selection in selections) {
    final split = selection.indexOf('=');
    if (split < 1) {
      throw ArgumentError('Expected NAME=git:REF or NAME=dir:PATH');
    }
    final name = selection.substring(0, split);
    final source = selection.substring(split + 1);
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(name) ||
        sources.containsKey(name) ||
        !(source.startsWith('git:') || source.startsWith('dir:'))) {
      throw ArgumentError('Invalid or duplicate source $selection');
    }
    sources[name] = source;
  }
  final stamp = DateTime.now().microsecondsSinceEpoch;
  final out = p.absolute(args['out'] as String? ??
      p.join(repo, 'build/value_store_profiles/$stamp-core'));
  if (Directory(out).existsSync()) throw StateError('Output exists: $out');
  Directory(out).createSync(recursive: true);
  final receipts = <Map<String, Object>>[];
  Future<String> run(String label, List<String> command,
      {Map<String, String>? env}) async {
    final before = Platform.isMacOS
        ? await commandOutput(['sysctl', '-n', 'vm.loadavg'])
        : 'unavailable';
    final watch = Stopwatch()..start();
    final result = await Process.run(command.first, command.skip(1).toList(),
        workingDirectory: repo, environment: env);
    watch.stop();
    File(p.join(out, '$label.log'))
        .writeAsStringSync('${result.stdout}${result.stderr}');
    receipts.add({
      'job': label,
      'command': command,
      'exit_code': result.exitCode,
      'seconds': watch.elapsedMilliseconds / 1000,
      'load_average_before': before
    });
    writeJson(p.join(out, 'receipts.json'), receipts);
    if (result.exitCode != 0) {
      throw StateError('$label failed: ${result.stderr}');
    }
    stdout.writeln('$label: passed');
    return result.stdout as String;
  }

  final sourceReceipts = <String, Object>{};
  final artifacts = <String, Object>{};
  final manifest = <String, Object>{
    'schema': 2,
    'host': 'dart_store_core',
    'dart': Platform.version,
    'machine': await commandOutput(['uname', '-m']),
    'os': Platform.operatingSystemVersion,
    'head': await commandOutput(['git', 'rev-parse', 'HEAD'], cwd: repo),
    'variants': sources.keys.toList(),
    'modes': modes,
    'suites': [suite],
    if (filter != null) 'operation_filter': filter,
    'passes': passes,
    'trials': trials,
    'warmups': warmups,
    'minimum_warmup_ms': warmupMs,
    'validation':
        'Release-active result checks outside each timed operation; see accompanying full-library validation',
    if (suite == 'manager_core')
      'isolation':
          'Actual store and manager methods with benchmark document/observer fixtures; not a full Loon engine benchmark',
    'source_snapshots': sourceReceipts,
    'artifacts': artifacts,
    'harness_sha256': {
      for (final name in [
        'run_core.dart',
        'profile_support.dart',
        'workloads/$suite.dart',
        if (suite == 'manager_core') 'manager_fixtures.dart',
      ])
        name: hashFile(p.join(repo, 'benchmark/value_store', name))
    },
  };
  void save() => writeJson(p.join(out, 'manifest.json'), manifest);
  save();
  for (final entry in sources.entries) {
    final name = entry.key;
    final root = p.join(out, name);
    Directory(root).createSync();
    final origin = entry.value.startsWith('git:')
        ? await commandOutput(['git', 'rev-parse', entry.value.substring(4)],
            cwd: repo)
        : p.absolute(entry.value.substring(4));
    final code = StringBuffer(
        "import 'dart:convert';\nimport 'dart:async';\nimport 'dart:collection';\ntypedef Json = Map<String, dynamic>;\n");
    final files = <String, Object>{};
    Future<String?> read(String path) async {
      if (entry.value.startsWith('git:')) {
        final result = await Process.run('git', ['show', '$origin:$path'],
            workingDirectory: repo);
        return result.exitCode == 0 ? result.stdout as String : null;
      }
      final file = File(p.join(origin, path));
      return file.existsSync() ? file.readAsStringSync() : null;
    }

    // Each file is read from the first of its paths that the source has. The implementation moved
    // under lib/src in 6.0.0, and older versions have no path helpers.
    for (final (paths, required) in [
      (
        [
          'lib/src/store/base_value_store.dart',
          'lib/store/base_value_store.dart'
        ],
        true
      ),
      (['lib/src/store/value_store.dart', 'lib/store/value_store.dart'], true),
      (
        [
          'lib/src/store/value_ref_store.dart',
          'lib/store/value_ref_store.dart'
        ],
        true
      ),
      (['lib/src/store/utils/paths.dart', 'lib/src/store/paths.dart'], false),
      (['lib/src/store/path_cache.dart'], false),
      if (suite == 'manager_core') ...[
        (
          [
            'lib/src/dependencies/dependency_manager.dart',
            'lib/dependency_manager.dart'
          ],
          true
        ),
        (
          [
            'lib/src/broadcast/broadcast_manager.dart',
            'lib/broadcast_manager.dart'
          ],
          true
        ),
        (
          ['lib/src/document_snapshot.dart', 'lib/document_snapshot.dart'],
          true
        ),
      ],
    ]) {
      String? path;
      String? source;
      for (final candidate in paths) {
        source = await read(candidate);
        if (source != null) {
          path = candidate;
          break;
        }
      }
      if (source == null || path == null) {
        if (required) throw StateError('${entry.value} has none of $paths');
        continue;
      }
      final snapshot = File(p.join(root, p.basename(path)))
        ..writeAsStringSync(source);
      files[path] = {'sha256': hashFile(snapshot.path), 'source': source};
      code.writeln(source.replaceFirst(RegExp(r"^part of '[^']+';"), ''));
    }
    if (suite == 'manager_core') {
      code.writeln(managerFixtures);
      File(p.join(root, 'manager_fixtures.dart'))
          .writeAsStringSync(managerFixtures);
    }
    sourceReceipts[name] = {
      'source': entry.value,
      'resolved': origin,
      'files': files
    };
    File(p.join(root, 'store.dart')).writeAsStringSync('$code');
    final support =
        File(p.join(repo, 'benchmark/value_store/profile_support.dart'))
            .readAsStringSync();
    File(p.join(root, 'profile_support.dart')).writeAsStringSync(replaceOnce(
        support,
        "import 'package:flutter/foundation.dart';",
        "const kReleaseMode = bool.fromEnvironment('CORE_AOT');"));
    final workload = suite == 'manager_core'
        ? managerWorkload
        : File(p.join(repo, 'benchmark/value_store/workloads/$suite.dart'))
            .readAsStringSync();
    File(p.join(root, 'workload.dart')).writeAsStringSync(workload
        .replaceFirst("'package:loon/loon.dart'", "'store.dart'")
        .replaceFirst("'package:loon/src/store/store.dart'", "'store.dart'")
        .replaceFirst("'../profile_support.dart'", "'profile_support.dart'"));
    File(p.join(root, 'main.dart')).writeAsStringSync('''
import 'dart:convert';
import 'dart:io';
import 'profile_support.dart';
import 'workload.dart';
void main() {
  ProfileResults.nativeHost = true;
  $entrypoint();
  final data = {...ProfileResults.completed.single, 'exit_code': 0};
  File(Platform.environment['PROFILE_OUTPUT']!).writeAsStringSync(jsonEncode(data));
}
''');
    if (modes.contains('aot')) {
      await run('$name-compile', [
        Platform.resolvedExecutable,
        'compile',
        'exe',
        '-DCORE_AOT=true',
        p.join(root, 'main.dart'),
        '-o',
        p.join(root, 'core')
      ]);
      artifacts[name] = hashFile(p.join(root, 'core'));
    }
    save();
  }
  final jobs = [
    for (final name in sources.keys)
      for (final mode in modes) (name, mode)
  ];
  for (var pass = 1; pass <= passes; pass++) {
    for (final (name, mode) in pass.isOdd ? jobs : jobs.reversed) {
      final label = '$pass-$name-$mode-$suite';
      await run(
          label,
          mode == 'aot'
              ? [p.join(out, name, 'core')]
              : [
                  Platform.resolvedExecutable,
                  '--enable-asserts',
                  p.join(out, name, 'main.dart')
                ],
          env: {
            'PROFILE_OUTPUT': p.join(out, '$label.json'),
            'PROFILE_VARIANT': name,
            'PROFILE_SUITE': suite,
            'PROFILE_WARMUPS': '$warmups',
            'PROFILE_WARMUP_MS': '$warmupMs',
            'PROFILE_TRIALS': '$trials',
            if (filter != null) 'PROFILE_FILTER': filter,
          });
    }
  }
  summarize(out);
}
