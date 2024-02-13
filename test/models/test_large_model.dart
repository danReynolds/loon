import 'package:loon/loon.dart';

class TestLargeModel {
  final String id;
  final double amount;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final double secondaryAmount;
  final String description;

  TestLargeModel({
    required this.id,
    required this.amount,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.secondaryAmount,
    required this.description,
  });

  TestLargeModel.fromJson(Json json)
      : id = json['id'],
        amount = json['amount'],
        name = json['name'],
        createdAt = DateTime.parse(json['createdAt']),
        updatedAt = DateTime.parse(json['updatedAt']),
        secondaryAmount = json['secondaryAmount'],
        description = json['description'];

  Json toJson() {
    return {
      "id": id,
      "amount": amount,
      "name": name,
      "createdAt": createdAt.toIso8601String(),
      "updatedAt": updatedAt.toIso8601String(),
      "secondaryAmount": secondaryAmount,
      "description": description,
    };
  }
}
