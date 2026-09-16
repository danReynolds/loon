import 'package:flutter_test/flutter_test.dart';
import 'workloads/dependency.dart' show profileDependencies;

void main() {
  test('dependency propagation and deletion profiles', profileDependencies);
}
