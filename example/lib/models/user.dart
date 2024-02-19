import 'package:loon/loon.dart';

class UserModel {
  final String name;

  UserModel({
    required this.name,
  });

  toJson() {
    return {
      "name": name,
    };
  }

  UserModel copyWith({
    String? name,
    String? id,
  }) {
    return UserModel(
      name: name ?? this.name,
    );
  }

  UserModel.fromJson(Json json) : name = json['name'];

  static Collection<UserModel> get store {
    return Loon.collection<UserModel>(
      'users',
      fromJson: UserModel.fromJson,
      toJson: (user) => user.toJson(),
    );
  }
}
