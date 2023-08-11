import 'package:flutter/material.dart';
import 'package:loon/loon.dart';

class ComputableStreamBuilder<T> extends StatelessWidget {
  final Computable<T> computable;
  final Widget Function(BuildContext, T) builder;

  const ComputableStreamBuilder({
    super.key,
    required this.computable,
    required this.builder,
  });

  @override
  build(context) {
    return StreamBuilder<T>(
      key: ObjectKey(computable),
      initialData: computable.get(),
      stream: computable.stream(),
      builder: (context, snap) => builder(context, snap.requireData),
    );
  }
}
