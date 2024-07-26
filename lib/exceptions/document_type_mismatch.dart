part of loon;

class DocumentTypeMismatchException<T> implements Exception {
  final DocumentSnapshot snap;

  DocumentTypeMismatchException(this.snap);

  @override
  String toString() =>
      'Document type mismatch: Requested type $T does not match existing type ${snap.data.runtimeType}';
}
