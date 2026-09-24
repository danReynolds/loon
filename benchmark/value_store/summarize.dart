import 'dart:io';
import 'package:path/path.dart' as p;
import 'tool_support.dart';

/// Requires a complete matrix and keeps each compilation mode separate.
void summarize(String root) {
  final manifest = readJson(p.join(root, 'manifest.json'));
  if (manifest['schema'] != 2) {
    throw StateError('Unsupported manifest schema ${manifest['schema']}.');
  }
  final modes = (manifest['modes'] as List).cast<String>();
  final variants = (manifest['variants'] as List).cast<String>();
  final suites = (manifest['suites'] as List).cast<String>();
  final groups =
      <(String, String, String, String), List<Map<String, dynamic>>>{};
  final raw = <String, Object>{};
  final namesBySuite = <String, Set<String>>{};
  for (var pass = 1; pass <= (manifest['passes'] as int); pass++) {
    for (final variant in variants) {
      for (final mode in modes) {
        for (final suite in suites) {
          final filename = '$pass-$variant-$mode-$suite.json';
          final path = p.join(root, filename);
          if (!File(path).existsSync()) {
            throw StateError('Incomplete run: missing $filename');
          }
          final data = readJson(path);
          final rows = (data['rows'] as List?)?.cast<Map<String, dynamic>>();
          if (data['exit_code'] != 0 ||
              data['mode'] != mode ||
              data['variant'] != variant ||
              data['suite'] != suite ||
              data['host'] != manifest['host'] ||
              rows == null ||
              rows.isEmpty) {
            throw StateError('Failed or misclassified result: $path');
          }
          final names = rows.map((row) => row['name'] as String).toSet();
          if (names.length != rows.length) {
            throw StateError('Duplicate operations: $path');
          }
          final previous = namesBySuite.putIfAbsent(suite, () => names);
          if (previous.length != names.length || !previous.containsAll(names)) {
            throw StateError('Operation sets differ between results: $path');
          }
          raw[filename] = data;
          for (final row in rows) {
            final samples = (row['samples_us'] as List).cast<num>();
            if (samples.length != manifest['trials'] ||
                samples.any((x) => !x.isFinite || x < 0)) {
              throw StateError('Invalid samples: $path / ${row['name']}');
            }
            (groups[(mode, suite, row['name'] as String, variant)] ??= [])
                .add(row);
          }
        }
      }
    }
  }
  final lines = <String>[
    '# Store and manager benchmarks',
    '',
    'Dart ${manifest['dart']}; ${manifest['machine']}; ${manifest['os']}.',
    '',
    'Isolated actual store sources: JIT = Dart VM with assertions; AOT = dart compile exe. '
        'This isolates store algorithms, not full Flutter-engine or mobile-device performance.',
    if (manifest['isolation'] case final String isolation) isolation,
    '',
    'Values are pooled medians in milliseconds, with the range of per-process '
        'medians (not a confidence interval). Setup, compilation and correctness '
        'checks are outside timed intervals.',
    '',
    'Validation: ${manifest['validation']}.',
    '',
  ];
  final summary = <Map<String, Object>>[];
  for (final mode in modes) {
    lines.addAll([
      '## $mode',
      '',
      '| Suite / operation | ${variants.join(' | ')} |',
      '| --- | ${List.filled(variants.length, '---:').join(' | ')} |'
    ]);
    final operations = groups.keys
        .where((key) => key.$1 == mode)
        .map((key) => (key.$2, key.$3))
        .toSet()
        .toList()
      ..sort((a, b) => '${a.$1}/${a.$2}'.compareTo('${b.$1}/${b.$2}'));
    for (final (suite, name) in operations) {
      final cells = <String>[];
      for (final variant in variants) {
        final rows = groups[(mode, suite, name, variant)]!;
        final samples = rows
            .expand((row) => (row['samples_us'] as List).cast<num>())
            .toList();
        final medians = rows
            .map((row) => median((row['samples_us'] as List).cast<num>()))
            .toList();
        final sorted = [...medians]..sort();
        final value = median(samples);
        cells.add(
            '${milliseconds(value)} (${milliseconds(sorted.first)}–${milliseconds(sorted.last)})');
        summary.add({
          'mode': mode,
          'suite': suite,
          'name': name,
          'variant': variant,
          'median_us': value,
          'process_medians_us': medians,
          'samples_us': samples
        });
      }
      lines.add('| $suite/$name | ${cells.join(' | ')} |');
    }
    lines.add('');
  }
  File(p.join(root, 'report.md')).writeAsStringSync(lines.join('\n'));
  writeJson(p.join(root, 'raw-results.json'), {
    'manifest': manifest,
    'runs': raw,
    'summary': summary,
    'summary_tool_sha256': hashFile(
        p.join(File.fromUri(Platform.script).parent.path, 'summarize.dart')),
  });
  stdout.writeln(p.join(root, 'report.md'));
}

void main(List<String> arguments) {
  if (arguments.length != 1) {
    throw ArgumentError(
        'Usage: dart run benchmark/value_store/summarize.dart RUN_DIRECTORY');
  }
  summarize(p.absolute(arguments.single));
}
