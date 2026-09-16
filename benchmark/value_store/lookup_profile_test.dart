import 'package:flutter_test/flutter_test.dart';
import 'workloads/lookup.dart' show profileLookups;

void main() {
  test('exact lookup and hierarchical operation profiles', profileLookups);
}
