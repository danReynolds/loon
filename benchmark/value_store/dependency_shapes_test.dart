import 'package:flutter_test/flutter_test.dart';
import 'workloads/dependency_shapes.dart';
import 'workloads/sparse_writes.dart';

void main() {
  test('dependency locality and graph workloads', profileDependencyShapes);
  test('sparse writes with zero or one dependent', profileSparseWrites);
}
