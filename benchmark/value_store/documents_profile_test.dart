import 'package:flutter_test/flutter_test.dart';
import 'workloads/documents.dart';

void main() {
  test('document construction, hashing and dependency rewiring checks',
      profileDocuments);
}
