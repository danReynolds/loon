part of loon;

abstract class StoreNode {
  final StoreNode? parent;
  final String name;
  Map<String, StoreNode>? children;

  StoreNode(
    this.name, {
    this.parent,
    this.children,
  });

  String get path {
    if (parent != null) {
      return "${parent!.path}__$name";
    }
    return name;
  }

  /// Recursively initialize the store nodes from the current node to the root.
  void _addChild(StoreNode child) {
    children ??= {};
    children![child.name] = child;
    parent?._addChild(this);
  }

  void _removeChild(StoreNode child) {
    final children = this.children;

    if (children == null) {
      return;
    }

    children.remove(child.name);

    if (children.isEmpty) {
      parent?._removeChild(this);
    }
  }
}
