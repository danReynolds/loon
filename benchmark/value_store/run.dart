import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import 'tool_support.dart';
import 'variants.dart';
import 'headless_host.dart';

const suiteNames = [
  'lookup',
  'store_core',
  'traversal',
  'traversal_apis',
  'iterable',
  'extraction',
  'extraction_cost',
  'dependency',
  'dependency_shapes',
  'sparse_writes',
  'documents'
];

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('out')
    ..addOption('library-source',
        help: 'Package directory supplying lib/ before applying each variant')
    ..addOption('store-baseline',
        help:
            'Package directory supplying frozen store sources for store_before')
    ..addOption('variants', defaultsTo: 'baseline,combined')
    ..addOption('modes', defaultsTo: 'jit,aot')
    ..addOption('suites', defaultsTo: suiteNames.join(','))
    ..addOption('passes', defaultsTo: '2')
    ..addOption('warmups', defaultsTo: '5')
    ..addOption('warmup-ms', defaultsTo: '250')
    ..addOption('trials', defaultsTo: '15')
    ..addOption('case', allowed: [
      '100k_shared',
      '10k_four_queries',
      '100k_100_groups',
      '20k_nested'
    ])
    ..addFlag('skip-validation', negatable: false)
    ..addFlag('build-only', negatable: false)
    ..addFlag('help', abbr: 'h', negatable: false);
  final args = parser.parse(arguments);
  if (args['help'] as bool) {
    stdout.writeln(
        'Dart runner for actual Loon in disposable Flutter hosts.\n${parser.usage}');
    return;
  }
  if (args.rest.isNotEmpty) {
    throw ArgumentError('Unexpected arguments: ${args.rest}');
  }
  if (!Platform.isMacOS) {
    throw UnsupportedError(
        'Native runner currently targets macOS; see README for device runs.');
  }
  List<String> selection(String name, List<String> allowed) {
    final values = (args[name] as String).split(',');
    if (values.toSet().length != values.length ||
        values.any((x) => !allowed.contains(x))) {
      throw ArgumentError('Unknown or duplicate $name: $values');
    }
    return values;
  }

  int count(String name, {int minimum = 1}) {
    final value = int.parse(args[name] as String);
    if (value < minimum) throw ArgumentError('$name must be >= $minimum');
    return value;
  }

  final storeBaseline = args['store-baseline'] as String?;
  final variants = selection('variants', [
    ...variantNames,
    if (storeBaseline != null) 'store_before',
  ]);
  final modes = selection('modes', ['jit', 'aot', 'profile']);
  final suites = selection('suites', suiteNames);
  final passes = count('passes');
  final trials = count('trials');
  final warmups = count('warmups');
  final warmupMs = count('warmup-ms', minimum: 0);
  final skipValidation = args['skip-validation'] as bool;
  final repo = File.fromUri(Platform.script).parent.parent.parent.path;
  final librarySource = p.absolute(args['library-source'] as String? ?? repo);
  if (!Directory(p.join(librarySource, 'lib')).existsSync()) {
    throw ArgumentError('No lib/ in $librarySource');
  }
  final stamp =
      DateTime.now().toIso8601String().replaceAll(RegExp(r'[^0-9]'), '');
  final out = p.absolute(args['out'] as String? ??
      p.join(repo, 'build/value_store_profiles/$stamp-native'));
  if (Directory(out).existsSync()) {
    throw StateError('Output directory already exists: $out');
  }
  final lock = p.join(repo, 'pubspec.lock');
  if (!File(lock).existsSync()) {
    throw StateError('Resolve root dependencies first.');
  }
  final locked = lockedVersions(lock);
  if (!locked.containsKey('fake_async')) {
    throw StateError('No fake_async in lockfile');
  }
  Directory(out).createSync(recursive: true);
  final receipts = <Map<String, Object>>[];
  Future<String> load() => commandOutput(['sysctl', '-n', 'vm.loadavg']);
  Future<void> run(String label, List<String> command, String cwd,
      {Map<String, String>? env, int timeoutSeconds = 600}) async {
    final before = await load();
    final watch = Stopwatch()..start();
    final logFile = File(p.join(out, '$label.log'));
    final log = logFile.openWrite();
    final process = await Process.start(command.first, command.skip(1).toList(),
        workingDirectory: cwd,
        environment: env,
        includeParentEnvironment: env == null);
    final streams = Future.wait([
      process.stdout.forEach(log.add),
      process.stderr.forEach(log.add),
    ]);
    var timedOut = false;
    final timer = Timer(Duration(seconds: timeoutSeconds), () {
      timedOut = true;
      process.kill(ProcessSignal.sigkill);
    });
    final status = await process.exitCode;
    timer.cancel();
    await streams;
    await log.close();
    watch.stop();
    final receipt = <String, Object>{
      'job': label,
      'command': command,
      'cwd': cwd,
      'exit_code': timedOut ? 124 : status,
      'seconds': watch.elapsedMilliseconds / 1000,
      'load_average_before': before,
      'load_average_after': await load()
    };
    receipts.add(receipt);
    writeJson(p.join(out, 'receipts.json'), receipts);
    stdout.writeln(jsonEncode(receipt));
    if (status != 0 || timedOut) {
      final text = logFile.readAsStringSync();
      stderr
          .writeln(text.substring(text.length > 8000 ? text.length - 8000 : 0));
      throw StateError('Failed $label; see ${logFile.path}');
    }
  }

  final flutter =
      jsonDecode(await commandOutput(['flutter', '--version', '--machine']));
  final variantHashes = <String, Object>{};
  final artifacts = <String, Object>{};
  final manifest = <String, Object?>{
    'schema': 2,
    'head': await commandOutput(['git', 'rev-parse', 'HEAD'], cwd: repo),
    'flutter': flutter,
    'machine': await commandOutput(['uname', '-m']),
    'os': Platform.operatingSystemVersion,
    'cpu_count': Platform.numberOfProcessors,
    'modes': modes,
    'variants': variants,
    'suites': suites,
    'passes': passes,
    'trials': trials,
    'warmups': warmups,
    'minimum_warmup_ms': warmupMs,
    'case': args['case'],
    if (storeBaseline != null) 'store_baseline': p.absolute(storeBaseline),
    'runner': 'dart',
    'headless': true,
    'library_source': librarySource,
    'validation': skipValidation
        ? 'skipped'
        : 'core and benchmark semantics before timing',
    'source_sha256': {
      ...sourceHashes(p.join(librarySource, 'lib'), librarySource),
      ...sourceHashes(p.join(repo, 'benchmark/value_store'), repo)
    },
    'root_lock_sha256': hashFile(lock),
    'resolved_hosted_versions': locked,
    'variant_sha256': variantHashes,
    'artifacts': artifacts,
  };
  void saveManifest() => writeJson(p.join(out, 'manifest.json'), manifest);
  saveManifest();
  final binaries = <(String, String), String>{};
  // Prepare and parse every variant before starting expensive host builds.
  for (final variant in variants) {
    final package = p.join(out, 'packages', variant);
    for (final directory in ['lib', 'test', 'benchmark/value_store']) {
      copyTree(p.join(directory == 'lib' ? librarySource : repo, directory),
          p.join(package, directory));
    }
    for (final name in [
      'pubspec.yaml',
      'pubspec.lock',
      'analysis_options.yaml'
    ]) {
      File(p.join(repo, name)).copySync(p.join(package, name));
    }
    if (variant == 'store_before') {
      for (final path in [
        'lib/store/base_value_store.dart',
        'lib/store/value_store.dart',
        'lib/store/value_ref_store.dart',
        'lib/utils/store.dart',
      ]) {
        File(p.join(storeBaseline!, path)).copySync(p.join(package, path));
      }
    } else {
      configureVariant(package, variant);
    }
    if (['batch_clean', 'scoped_clean', 'scoped_guard'].contains(variant)) {
      await run(
          '$variant-format',
          [
            Platform.resolvedExecutable,
            'format',
            'lib/broadcast_manager.dart',
            'lib/dependency_manager.dart'
          ],
          package);
    }
    variantHashes[variant] = sourceHashes(p.join(package, 'lib'), package);
    saveManifest();
    await run(
        '$variant-syntax',
        [Platform.resolvedExecutable, 'format', '--output=none', 'lib'],
        package);
  }
  // Finish all validation/builds before timing to avoid compiler load.
  for (final variant in variants) {
    final package = p.join(out, 'packages', variant);
    await run(
        '$variant-resolve', ['flutter', 'pub', 'get', '--offline'], package);
    if (!skipValidation) {
      await run(
          '$variant-validation',
          [
            'flutter',
            'test',
            '--no-pub',
            'test/core',
            'benchmark/value_store/traversal_profile_test.dart',
            'benchmark/value_store/iterable_profile_test.dart',
            'benchmark/value_store/extraction_profile_test.dart',
            'benchmark/value_store/extraction_cost_test.dart',
            'benchmark/value_store/traversal_apis_test.dart',
            'benchmark/value_store/collection_lookup_demo_test.dart',
            'benchmark/value_store/documents_profile_test.dart',
            'benchmark/value_store/store_core_profile_test.dart',
            'benchmark/value_store/path_cache_test.dart',
            'benchmark/value_store/dependency_shapes_test.dart',
            'benchmark/value_store/document_values_test.dart',
            // These historical controls contain sets, not serializable entries.
            if (['document_paths', 'document_before_paths']
                .contains(variant)) ...[
              '--name',
              '^(?!.*Dependency entries use standard JSON serialization)',
            ],
            '--concurrency=1',
            '--reporter',
            'expanded'
          ],
          package,
          env: {
            ...Platform.environment,
            'PROFILE_WARMUPS': '1',
            'PROFILE_WARMUP_MS': '0',
            'PROFILE_TRIALS': '1'
          });
    }
    final host = p.join(out, 'hosts', variant);
    await run(
        '$variant-create-host',
        [
          'flutter',
          'create',
          '--no-pub',
          '--empty',
          '--platforms',
          'macos',
          '--project-name',
          'loon_profile',
          '--org',
          'dev.loon.benchmark',
          host
        ],
        repo);
    configureHeadlessHost(host);
    final spec = StringBuffer('''name: loon_profile
publish_to: none
version: 1.0.0+1
environment:
  sdk: '>=3.0.0 <4.0.0'
dependencies:
  flutter:
    sdk: flutter
  loon:
    path: ${jsonEncode(package)}
  fake_async: ${jsonEncode(locked['fake_async'])}
dependency_overrides:
''');
    locked.forEach(
        (name, version) => spec.writeln('  $name: ${jsonEncode(version)}'));
    File(p.join(host, 'pubspec.yaml')).writeAsStringSync('$spec');
    File(lock).copySync(p.join(host, 'pubspec.lock'));
    for (final name in ['DebugProfile', 'Release']) {
      // Only the throwaway host needs permission to write benchmark JSON.
      await run(
          '$variant-$name-entitlements',
          [
            '/usr/libexec/PlistBuddy',
            '-c',
            'Set :com.apple.security.app-sandbox false',
            p.join(host, 'macos/Runner/$name.entitlements')
          ],
          repo);
    }
    await run(
        '$variant-host-resolve', ['flutter', 'pub', 'get', '--offline'], host);
    final actual = lockedVersions(p.join(host, 'pubspec.lock'));
    for (final entry in actual.entries) {
      if (locked[entry.key] != entry.value) {
        throw StateError('Unexpected host version: $entry');
      }
    }
    final target = p.join(package, 'benchmark/value_store/native_main.dart');
    for (final mode in modes) {
      final buildMode =
          {'jit': 'debug', 'aot': 'release', 'profile': 'profile'}[mode]!;
      await run(
          '$variant-$mode-build',
          [
            'flutter',
            'build',
            'macos',
            '--no-pub',
            '--$buildMode',
            '--target',
            target
          ],
          host,
          timeoutSeconds: 1200);
      final product = '${buildMode[0].toUpperCase()}${buildMode.substring(1)}';
      final app =
          p.join(host, 'build/macos/Build/Products/$product/loon_profile.app');
      final binary = p.join(app, 'Contents/MacOS/loon_profile');
      if (!File(binary).existsSync()) throw StateError('No binary at $binary');
      binaries[(variant, mode)] = binary;
      artifacts['$variant/$mode'] = {
        'app': app,
        'executable_sha256': hashFile(binary),
        'dart_artifacts': {
          for (final file in filesUnder(app))
            if (['kernel_blob.bin', 'App'].contains(p.basename(file.path)))
              p.relative(file.path, from: app): hashFile(file.path)
        },
        'host_lock_sha256': hashFile(p.join(host, 'pubspec.lock')),
        'host_source_sha256': {
          for (final name in ['Info.plist', 'AppDelegate.swift'])
            name: hashFile(p.join(host, 'macos/Runner', name)),
        }
      };
      saveManifest();
    }
  }
  final jobs = [
    for (final variant in variants)
      for (final mode in modes)
        for (final suite in suites) (variant, mode, suite)
  ];
  if (args['build-only'] as bool) {
    stdout.writeln('Built and validated hosts: $out');
    return;
  }
  for (var pass = 0; pass < passes; pass++) {
    for (final (variant, mode, suite) in pass.isEven ? jobs : jobs.reversed) {
      final label = '${pass + 1}-$variant-$mode-$suite';
      final output = p.join(out, '$label.json');
      final env = {
        ...Platform.environment,
        'PROFILE_VARIANT': variant,
        'PROFILE_EXPECT_MODE': mode,
        'PROFILE_SUITE': suite,
        'PROFILE_WARMUPS': '$warmups',
        'PROFILE_WARMUP_MS': '$warmupMs',
        'PROFILE_TRIALS': '$trials',
        'PROFILE_ORDER': pass.isEven ? 'forward' : 'reverse',
        'PROFILE_OUTPUT': output,
        'PROFILE_EXIT': 'true'
      };
      if (args['case'] != null) {
        env['PROFILE_CASE'] = args['case'] as String;
      } else {
        env.remove('PROFILE_CASE');
      }
      await run(label, [binaries[(variant, mode)]!], repo, env: env);
      final data = readJson(output);
      if (data['exit_code'] != 0 ||
          data['mode'] != mode ||
          data['headless'] != true ||
          data['host'] != 'flutter_app') {
        throw StateError('Failed or misclassified result: $output');
      }
    }
  }
  await run(
      'summary',
      [
        Platform.resolvedExecutable,
        'run',
        p.join(repo, 'benchmark/value_store/summarize.dart'),
        out
      ],
      repo);
  stdout.writeln(out);
}
