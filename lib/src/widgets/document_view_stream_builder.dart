import 'package:flutter/material.dart';
import 'package:loon/src/loon.dart';

/// Builds from a [DocumentView], such as a document of a [CollectionView], with its read-only
/// snapshots. An ordinary [Document] is also a document view.
class DocumentViewStreamBuilder<T> extends StatefulWidget {
  final DocumentView<T> doc;
  final Widget Function(BuildContext, DocumentSnapshotView<T>?) builder;

  const DocumentViewStreamBuilder({
    super.key,
    required this.doc,
    required this.builder,
  });

  @override
  DocumentViewStreamBuilderState<T> createState() =>
      DocumentViewStreamBuilderState<T>();
}

class DocumentViewStreamBuilderState<T>
    extends State<DocumentViewStreamBuilder<T>> {
  late ObservableDocumentView<T> _observable = widget.doc.observe();

  @override
  void didUpdateWidget(covariant DocumentViewStreamBuilder<T> oldWidget) {
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
