import 'package:flutter/material.dart';
import 'package:loon/loon.dart';
import 'package:loon/widgets/observable_stream_builder.dart';

class QueryStreamBuilder<T> extends StatelessWidget {
  final Query<T> query;
  final Widget Function(BuildContext, List<DocumentSnapshot<T>>) builder;

  const QueryStreamBuilder({
    super.key,
    required this.query,
    required this.builder,
  });

  @override
  build(context) {
    return ObservableStreamBuilder(
      observable: query.observe(),
      builder: builder,
    );
  }
}
