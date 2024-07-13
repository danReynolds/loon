import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';

class DocumentSnapshotMatcher<T> extends Matcher {
  DocumentSnapshot<T?>? expected;
  late DocumentSnapshot<T?>? actual;
  DocumentSnapshotMatcher(this.expected);

  @override
  Description describe(Description description) {
    return description.add(
      "has expected document ID: ${expected?.id}, data: ${expected?.data}",
    );
  }

  @override
  Description describeMismatch(
    dynamic item,
    Description mismatchDescription,
    Map<dynamic, dynamic> matchState,
    bool verbose,
  ) {
    return mismatchDescription.add(
      "Expected: $item, Actual: ${matchState['actual']}",
    );
  }

  @override
  bool matches(actual, Map matchState) {
    this.actual = actual;

    final actualData = actual?.data;
    final expectedData = expected?.data;

    if (actual.doc.path != expected?.doc.path) {
      return false;
    }

    if (expectedData == null) {
      return actualData == null;
    }

    if (expectedData is Json) {
      return actualData is Json && mapEquals(actualData, expectedData);
    }

    return expectedData == actualData;
  }
}
