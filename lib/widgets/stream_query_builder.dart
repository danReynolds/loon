import 'package:flutter/material.dart';
import 'package:loon/loon.dart';

class StreamQueryBuilder<T> extends StatefulWidget {
  final Query<T> query;
  final Widget Function(BuildContext, List<DocumentSnapshot<T>>) builder;

  const StreamQueryBuilder({
    super.key,
    required this.query,
    required this.builder,
  });

  @override
  StreamQueryState<T> createState() => StreamQueryState<T>();
}

class StreamQueryState<T> extends State<StreamQueryBuilder<T>> {
  late final WatchQuery<T> _watchQuery;

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
      initialData: _watchQuery.snapshot,
      stream: _watchQuery.stream,
      builder: (context, snap) => widget.builder(context, snap.requireData),
    );
  }
}
