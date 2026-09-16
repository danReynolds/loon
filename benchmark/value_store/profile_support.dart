import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

// Environment overrides make one compiled desktop binary reusable. Dart defines
// provide the same settings for Flutter runs on physical mobile devices.
const _defines = {
  'PROFILE_WARMUPS': String.fromEnvironment('PROFILE_WARMUPS'),
  'PROFILE_WARMUP_MS': String.fromEnvironment('PROFILE_WARMUP_MS'),
  'PROFILE_TRIALS': String.fromEnvironment('PROFILE_TRIALS'),
  'PROFILE_ORDER': String.fromEnvironment('PROFILE_ORDER'),
  'PROFILE_CASE': String.fromEnvironment('PROFILE_CASE'),
  'PROFILE_SUITE': String.fromEnvironment('PROFILE_SUITE'),
  'PROFILE_VARIANT': String.fromEnvironment('PROFILE_VARIANT'),
  'PROFILE_EXPECT_MODE': String.fromEnvironment('PROFILE_EXPECT_MODE'),
  'PROFILE_START_DELAY_MS': String.fromEnvironment('PROFILE_START_DELAY_MS'),
  'PROFILE_EXIT': String.fromEnvironment('PROFILE_EXIT'),
};

String? profileSetting(String name) {
  final value = Platform.environment[name] ?? _defines[name];
  return value == null || value.isEmpty ? null : value;
}

final warmups = int.parse(profileSetting('PROFILE_WARMUPS') ?? '5');
final warmupMillis = int.parse(profileSetting('PROFILE_WARMUP_MS') ?? '250');
final trials = int.parse(profileSetting('PROFILE_TRIALS') ?? '15');
String get profileMode =>
    kReleaseMode ? 'aot' : (kProfileMode ? 'profile' : 'jit');

void check(bool condition, String message) {
  // Dart assert is disabled in release; benchmark validation must remain active.
  if (!condition) throw StateError(message);
}

Iterable<bool> samplePhases() sync* {
  check(warmups >= 1 && trials >= 1 && warmupMillis >= 0, 'Invalid repetition');
  final elapsed = Stopwatch()..start();
  var count = 0;
  while (count < warmups || elapsed.elapsedMilliseconds < warmupMillis) {
    yield false;
    count++;
  }
  for (var i = 0; i < trials; i++) {
    yield true;
  }
}

class ProfileResults {
  static final completed = <Map<String, Object?>>[];
  static bool nativeHost = false;
  final rows = <Map<String, Object>>[];

  void measure(String name, int Function() action,
      {required int expected, int operations = 1, void Function()? prepare}) {
    final samples = <int>[];
    int? firstSample;
    for (final recordSample in samplePhases()) {
      prepare?.call();
      final watch = Stopwatch()..start();
      final actual = action();
      watch.stop();
      check(actual == expected, '$name: expected $expected, got $actual');
      firstSample ??= watch.elapsedMicroseconds;
      if (recordSample) samples.add(watch.elapsedMicroseconds);
    }
    add(name, samples,
        {'operations': operations, 'first_sample_us': firstSample!});
  }

  void add(String name, List<int> samples,
      [Map<String, Object> details = const {}]) {
    final ordered = List.of(samples)..sort();
    final middle = ordered.length ~/ 2;
    final median = ordered.length.isOdd
        ? ordered[middle].toDouble()
        : (ordered[middle - 1] + ordered[middle]) / 2;
    rows.add(
        {'name': name, ...details, 'median_us': median, 'samples_us': samples});
  }

  void save() {
    final data = {
      'schema': 2,
      'dart': Platform.version,
      'os': Platform.operatingSystem,
      'mode': profileMode,
      'host': nativeHost ? 'flutter_app' : 'flutter_test',
      'variant': profileSetting('PROFILE_VARIANT') ?? 'workspace',
      'suite': profileSetting('PROFILE_SUITE'),
      'warmups': warmups,
      'minimum_warmup_ms': warmupMillis,
      'trials': trials,
      'rows': rows,
    };
    completed.add(data);
    if (nativeHost) return;
    final json = const JsonEncoder.withIndent('  ').convert(data);
    final output = Platform.environment['PROFILE_OUTPUT'];
    if (output != null) File(output).writeAsStringSync(json);
    // ignore: avoid_print
    print(json);
  }
}
