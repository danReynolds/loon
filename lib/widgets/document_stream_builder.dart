import 'package:flutter/material.dart';
import 'package:loon/loon.dart';
import 'package:loon/widgets/computable_stream_builder.dart';

class DocumentStreamBuilder<T> extends StatelessWidget {
  final Document<T> doc;
  final Widget Function(BuildContext, DocumentSnapshot<T>?) builder;

  const DocumentStreamBuilder({
    super.key,
    required this.doc,
    required this.builder,
  });

  @override
  build(context) {
    return ComputableStreamBuilder(
      computable: doc.observe(),
      builder: builder,
    );
  }
}
