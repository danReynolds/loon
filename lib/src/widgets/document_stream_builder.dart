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
      _release(oldWidget.doc);
      _observable = widget.doc.observe();
    }
  }

  // An observed document returns itself from observe(). Its lifetime belongs to the caller
  // that passed it in, so the builder only disposes an observer it created.
  void _release(DocumentView<T> doc) {
    if (!identical(_observable, doc)) {
      _observable.dispose();
    }
  }

  @override
  void dispose() {
    _release(widget.doc);
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
