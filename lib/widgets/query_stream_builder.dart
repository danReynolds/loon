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
  QueryStreamBuilderState<T> createState() => QueryStreamBuilderState<T>();
}

class QueryStreamBuilderState<T> extends State<QueryStreamBuilder<T>> {
  late final ObservableQuery<T> _observable;

  @override
  initState() {
    super.initState();
    _observable = widget.query.observe();
  }

  @override
  void didUpdateWidget(covariant QueryStreamBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.query != widget.query) {
      _observable.dispose();
      _observable = widget.query.observe();
    }
  }

  @override
  build(context) {
    return StreamBuilder<List<DocumentSnapshot<T>>>(
      initialData: _observable.get(),
      stream: _observable.stream(),
      builder: (context, snap) => widget.builder(context, snap.data!),
    );
  }
}
