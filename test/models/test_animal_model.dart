import 'package:loon/loon.dart';

/// A sealed model hierarchy stored in a single collection, used to test narrowing
/// the collection's base [TestAnimalModel] type to one of its concrete subtypes
/// through a [CollectionView].
sealed class TestAnimalModel {
  final String name;

  const TestAnimalModel(this.name);

  static Collection<TestAnimalModel> get store {
    return Loon.collection<TestAnimalModel>(
      'animals',
      fromJson: TestAnimalModel.fromJson,
      toJson: (animal) => animal.toJson(),
    );
  }

  static TestAnimalModel fromJson(Json json) {
    return switch (json['type']) {
      'dog' => TestDogModel(json['name']),
      'cat' => TestCatModel(json['name']),
      _ => throw ArgumentError('Unknown animal type: ${json['type']}'),
    };
  }

  Json toJson();

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is TestAnimalModel) {
      return other.runtimeType == runtimeType && other.name == name;
    }
    return false;
  }

  @override
  int get hashCode => Object.hashAll([runtimeType, name]);

  @override
  toString() {
    return "$runtimeType:$name";
  }
}

class TestDogModel extends TestAnimalModel {
  const TestDogModel(super.name);

  @override
  Json toJson() {
    return {
      "type": 'dog',
      "name": name,
    };
  }
}

class TestCatModel extends TestAnimalModel {
  const TestCatModel(super.name);

  @override
  Json toJson() {
    return {
      "type": 'cat',
      "name": name,
    };
  }
}
