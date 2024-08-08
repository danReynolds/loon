import 'package:loon/loon.dart';

class TestUserModel {
  final String name;

  TestUserModel(this.name);

  static Collection<TestUserModel> get store {
    return Loon.collection<TestUserModel>(
      'users',
      fromJson: TestUserModel.fromJson,
      toJson: (user) => user.toJson(),
    );
  }

  TestUserModel.fromJson(Json json) : name = json['name'];

  Json toJson() {
    return {
      "name": name,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is TestUserModel) {
      return name == other.name;
    }
    return false;
  }

  @override
  int get hashCode => Object.hashAll([name]);

  @override
  toString() {
    return "TestUserModel:$name";
  }
}
