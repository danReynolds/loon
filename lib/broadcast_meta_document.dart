import 'package:loon/loon.dart';

class BroadcastMetaDocument<T> {
  final BroadcastDocument<T> doc;
  final BroadcastEventTypes type;
  final DocumentSnapshot<T>? prevSnap;
  final DocumentSnapshot<T>? snap;

  BroadcastMetaDocument(
    this.doc,
    this.type, {
    required this.prevSnap,
    required this.snap,
  });
}
