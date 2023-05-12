import 'package:flutter/material.dart';
import 'package:loon/loon.dart';

class DocumentStreamBuilder<T> extends StatefulWidget {
  final Document<T> doc;
  final Widget Function(BuildContext, DocumentSnapshot<T>?) builder;

  const DocumentStreamBuilder({
    super.key,
    required this.doc,
    required this.builder,
  });

  @override
  DocumentStreamState<T> createState() => DocumentStreamState<T>();
}

class DocumentStreamState<T> extends State<DocumentStreamBuilder<T>> {
  late ObservableDocument<T> _observableDoc;

  @override
  void didUpdateWidget(covariant DocumentStreamBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.doc != widget.doc) {
      _observableDoc.dispose();
      _observableDoc = widget.doc.asObservable();
    }
  }

  @override
  void initState() {
    super.initState();

    _observableDoc = widget.doc.asObservable();
  }

  @override
  void dispose() {
    super.dispose();
    _observableDoc.dispose();
  }

  @override
  build(context) {
    return StreamBuilder<DocumentSnapshot<T>?>(
      key: ObjectKey(_observableDoc),
      initialData: _observableDoc.value,
      stream: _observableDoc.stream(),
      builder: (context, snap) => widget.builder(context, snap.data),
    );
  }
}
