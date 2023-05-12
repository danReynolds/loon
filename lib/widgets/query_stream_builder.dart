import 'package:flutter/material.dart';
import 'package:loon/loon.dart';

class QueryStreamBuilder<T> extends StatefulWidget {
  final Query<T> query;
  final Widget Function(BuildContext, List<DocumentSnapshot<T>>) builder;

  const QueryStreamBuilder({
    super.key,
    required this.query,
    required this.builder,
  });

  @override
  StreamQueryState<T> createState() => StreamQueryState<T>();
}

class StreamQueryState<T> extends State<QueryStreamBuilder<T>> {
  late WatchQuery<T> _watchQuery;

  @override
  void didUpdateWidget(covariant QueryStreamBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.query != widget.query) {
      _watchQuery.dispose();
      _watchQuery = widget.query.watch();
    }
  }

  @override
  void initState() {
    super.initState();

    _watchQuery = widget.query.watch();
  }

  @override
  void dispose() {
    super.dispose();
    _watchQuery.dispose();
  }

  @override
  build(context) {
    return StreamBuilder<List<DocumentSnapshot<T>>>(
      key: ObjectKey(_watchQuery),
      initialData: _watchQuery.snapshot,
      stream: _watchQuery.stream,
      builder: (context, snap) => widget.builder(context, snap.requireData),
    );
  }
}
