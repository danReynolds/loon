import 'package:flutter/material.dart';
import 'package:loon/loon.dart';

class ObservableStreamBuilder<T, S> extends StatelessWidget {
  final BroadcastObserver<T, S> observable;
  final Widget Function(BuildContext, T) builder;

  const ObservableStreamBuilder({
    super.key,
    required this.observable,
    required this.builder,
  });

  @override
  build(context) {
    return StreamBuilder<T>(
      initialData: observable.get(),
      stream: observable.stream(),
      builder: (context, snap) => builder(context, snap.data as T),
    );
  }
}
