import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:uuid/uuid.dart';
import '../models/test_large_model.dart';

const uuid = Uuid();

TestLargeModel generateRandomModel() {
  var random = Random();
  return TestLargeModel(
    id: uuid.v4(),
    amount: random.nextDouble() * 100,
    name: 'Name ${random.nextInt(100)}',
    createdAt: DateTime.now().subtract(Duration(days: random.nextInt(100))),
    updatedAt: DateTime.now(),
    secondaryAmount: random.nextDouble() * 200,
    description: 'Description ${random.nextInt(100)}',
  );
}

Future<void> generateLargeModelSampleFile(int size) {
  List<TestLargeModel> models =
      List.generate(size, (_) => generateRandomModel());

  final modelsMap = models.fold({}, (acc, model) {
    acc['users:${model.id}'] = model.toJson();
    return acc;
  });

  String jsonContent = jsonEncode(modelsMap);
  File file = File('./test/samples/large_model_sample.json');
  return file.writeAsString(jsonContent);
}
