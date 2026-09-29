import 'package:flutter/material.dart';
import 'package:loon/src/loon.dart';

class DocumentStreamBuilder<T> extends StatefulWidget {
  final DocumentView<T> doc;
  final Widget Function(BuildContext, DocumentSnapshotView<T>?) builder;

  const DocumentStreamBuilder({
    super.key,
    required this.doc,
    required this.builder,
  });

  @override
  DocumentStreamBuilderState<T> createState() =>
      DocumentStreamBuilderState<T>();
}

class DocumentStreamBuilderState<T> extends State<DocumentStreamBuilder<T>> {
  late ObservableDocumentView<T> _observable = widget.doc.observe();

  @override
  void didUpdateWidget(covariant DocumentStreamBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.doc != widget.doc) {
      _observable.dispose();
      _observable = widget.doc.observe();
    }
  }

  @override
  void dispose() {
    _observable.dispose();
    super.dispose();
  }

  @override
  build(context) {
    return StreamBuilder<DocumentSnapshotView<T>?>(
      initialData: _observable.get(),
      stream: _observable.stream(),
      builder: (context, snap) => widget.builder(context, snap.data),
    );
  }
}
