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
  late ObservableQuery<T> _observableQuery;

  @override
  void didUpdateWidget(covariant QueryStreamBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.query != widget.query) {
      _observableQuery.dispose();
      _observableQuery = widget.query.asObservable();
    }
  }

  @override
  void initState() {
    super.initState();

    _observableQuery = widget.query.asObservable();
  }

  @override
  void dispose() {
    super.dispose();
    _observableQuery.dispose();
  }

  @override
  build(context) {
    return StreamBuilder<List<DocumentSnapshot<T>>>(
      key: ObjectKey(_observableQuery),
      initialData: _observableQuery.value,
      stream: _observableQuery.stream(),
      builder: (context, snap) => widget.builder(context, snap.requireData),
    );
  }
}
