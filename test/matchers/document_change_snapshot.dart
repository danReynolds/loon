import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';

import '../models/test_user_model.dart';

class DocumentChangeSnapshotMatcher<T> extends Matcher {
  DocumentChangeSnapshot<T?>? expected;
  late DocumentChangeSnapshot<T?>? actual;
  DocumentChangeSnapshotMatcher(this.expected);

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

    if (expected == null) {
      return actual == null;
    }

    if (actual is! DocumentChangeSnapshot<T>) {
      return false;
    }

    final actualData = actual.data;
    final expectedData = expected?.data;

    final prevActualData = actual.prevData;
    final prevExpectedData = expected!.prevData;

    if (actual.doc.path != expected?.doc.path) {
      return false;
    }

    if (expected!.event != actual.event) {
      return false;
    }

    if (expectedData == null) {
      return actualData == null;
    }

    if (prevExpectedData == null) {
      return prevActualData == null;
    }

    if (expectedData is Json) {
      return actualData is Json && mapEquals(actualData, expectedData);
    }

    if (expectedData is TestUserModel) {
      return actualData is TestUserModel && expectedData == actualData;
    }

    if (prevExpectedData is Json) {
      return prevActualData is Json &&
          mapEquals(prevExpectedData, prevActualData);
    }

    if (prevExpectedData is TestUserModel) {
      return prevActualData is TestUserModel &&
          prevExpectedData == prevActualData;
    }

    return false;
  }
}
