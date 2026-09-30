import 'package:flutter/material.dart';
import 'package:loon/src/loon.dart';

/// Builds from a [QueryView], such as a [CollectionView] or one of its queries, with its
/// read-only snapshots. An ordinary [Query] is also a query view.
class QueryViewStreamBuilder<T> extends StatefulWidget {
  final QueryView<T> query;
  final Widget Function(BuildContext, List<DocumentSnapshotView<T>>) builder;

  const QueryViewStreamBuilder({
    super.key,
    required this.query,
    required this.builder,
  });

  @override
  QueryViewStreamBuilderState<T> createState() =>
      QueryViewStreamBuilderState<T>();
}

class QueryViewStreamBuilderState<T> extends State<QueryViewStreamBuilder<T>> {
  late ObservableQueryView<T> _observable = widget.query.observe();

  @override
  void didUpdateWidget(covariant QueryViewStreamBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.query != widget.query) {
      _release(oldWidget.query);
      _observable = widget.query.observe();
    }
  }

  // An observed query returns itself from observe(). Its lifetime belongs to the caller
  // that passed it in, so the builder only disposes an observer it created.
  void _release(QueryView<T> query) {
    if (!identical(_observable, query)) {
      _observable.dispose();
    }
  }

  @override
  void dispose() {
    _release(widget.query);
    super.dispose();
  }

  @override
  build(context) {
    return StreamBuilder<List<DocumentSnapshotView<T>>>(
      initialData: _observable.get(),
      stream: _observable.stream(),
      builder: (context, snap) => widget.builder(context, snap.data!),
    );
  }
}
