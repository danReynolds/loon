import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'profile_support.dart';
import 'workloads/dependency.dart' show profileDependencies;
import 'workloads/dependency_retention.dart';
import 'workloads/documents.dart' show profileDocuments;
import 'workloads/extraction.dart' show profileExtraction;
import 'workloads/extraction_cost.dart' show profileExtractionCost;
import 'workloads/iterable.dart' show profileIterable;
import 'workloads/lookup.dart' show profileLookups;
import 'workloads/traversal.dart' show profileTraversal;
import 'workloads/traversal_apis.dart' show profileTraversalApis;

/// Entrypoint for an isolated Flutter host. The same workloads also run through
/// the *_profile_test.dart wrappers; no stand-in store or compiler shims.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ProfileResults.nativeHost = true;
  runApp(const Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: Text('Running Loon ValueStore benchmarks')),
  ));
  await WidgetsBinding.instance.endOfFrame;
  await Future<void>.delayed(Duration(
      milliseconds:
          int.parse(profileSetting('PROFILE_START_DELAY_MS') ?? '250')));

  var status = 0;
  final rssBefore = ProcessInfo.currentRss;
  final payload = <String, Object?>{};
  try {
    final expectedMode = profileSetting('PROFILE_EXPECT_MODE');
    check(expectedMode == null || expectedMode == profileMode,
        'Expected $expectedMode, running $profileMode');
    final suite = profileSetting('PROFILE_SUITE') ?? 'iterable';
    if (suite == 'dependency_retention') {
      payload.addAll(await captureDependencyRetention());
    } else {
      final run = {
        'lookup': profileLookups,
        'traversal': profileTraversal,
        'traversal_apis': profileTraversalApis,
        'iterable': profileIterable,
        'extraction': profileExtraction,
        'extraction_cost': profileExtractionCost,
        'dependency': profileDependencies,
        'documents': profileDocuments,
      }[suite];
      check(run != null, 'Unknown suite $suite');
      run!();
      check(
          ProfileResults.completed.length == 1, 'Expected one workload result');
      payload.addAll(ProfileResults.completed.single);
    }
  } catch (error, stack) {
    status = 1;
    payload.addAll({'error': '$error', 'stack': '$stack', 'mode': profileMode});
  }
  payload.addAll({
    'exit_code': status,
    // Process RSS includes Flutter and native libraries. It is diagnostic
    // context, not an allocation count or a retained Dart heap measurement.
    'process_rss_before': rssBefore,
    'process_rss_after': ProcessInfo.currentRss,
    'process_peak_rss': ProcessInfo.maxRss,
  });
  final output = Platform.environment['PROFILE_OUTPUT'];
  if (output != null) {
    File(output)
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(payload));
  }
  // Small lines survive mobile log limits; the runner can reconstruct JSON.
  final encoded = base64.encode(utf8.encode(jsonEncode(payload)));
  // ignore: avoid_print
  print('LOON_PROFILE_BEGIN');
  for (var i = 0; i < encoded.length; i += 800) {
    // ignore: avoid_print
    print(
        'LOON_PROFILE_DATA:${encoded.substring(i, (i + 800).clamp(0, encoded.length))}');
  }
  // ignore: avoid_print
  print('LOON_PROFILE_END');
  if (profileSetting('PROFILE_EXIT') != 'false') exit(status);
  runApp(Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
        child: Text(status == 0 ? 'Benchmarks complete' : 'Benchmarks failed')),
  ));
}
