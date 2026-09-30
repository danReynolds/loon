import 'package:flutter/material.dart';
import 'package:loon/src/loon.dart';

class QueryStreamBuilder<T> extends StatefulWidget {
  final Queryable<T> query;
  final Widget Function(BuildContext, List<DocumentSnapshotView<T>>) builder;

  const QueryStreamBuilder({
    super.key,
    required this.query,
    required this.builder,
  });

  @override
  QueryStreamBuilderState<T> createState() => QueryStreamBuilderState<T>();
}

class QueryStreamBuilderState<T> extends State<QueryStreamBuilder<T>> {
  late ObservableQueryView<T> _observable = widget.query.toQuery().observe();

  @override
  void didUpdateWidget(covariant QueryStreamBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.query != widget.query) {
      _release(oldWidget.query);
      _observable = widget.query.toQuery().observe();
    }
  }

  // An observed query returns itself from observe(). Its lifetime belongs to the caller
  // that passed it in, so the builder only disposes an observer it created.
  void _release(Queryable<T> query) {
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
