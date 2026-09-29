import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

// Settings come from the environment, so one compiled program serves every run.
String? profileSetting(String name) {
  final value = Platform.environment[name];
  return value == null || value.isEmpty ? null : value;
}

final warmups = int.parse(profileSetting('PROFILE_WARMUPS') ?? '5');
final warmupMillis = int.parse(profileSetting('PROFILE_WARMUP_MS') ?? '250');
final trials = int.parse(profileSetting('PROFILE_TRIALS') ?? '15');
String get profileMode => kReleaseMode ? 'aot' : 'jit';

void check(bool condition, String message) {
  // Dart assert is disabled in release; benchmark validation must remain active.
  if (!condition) throw StateError(message);
}

final _garbage = List<Object?>.filled(1024, null);

/// Allocates short-lived objects until the young generation has been collected a few times, so
/// objects that a sample's setup allocated are promoted instead of copied during the sample.
void settleHeap() {
  for (var i = 0; i < 1 << 18; i++) {
    _garbage[i & 1023] = List<int>.filled(8, i);
  }
  _garbage.fillRange(0, _garbage.length, null);
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
      'host': nativeHost ? 'dart_store_core' : 'flutter_test',
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
