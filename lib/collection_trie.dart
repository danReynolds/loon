class CollectionTrie<T> {
  late final CollectionTrieNode<T> root;
  final T Function()? onCreate;
  final void Function(String path)? onEvict;

  CollectionTrie({
    this.onCreate,
    this.onEvict,
  }) {
    root = CollectionTrieNode(
      path: '',
      collection: '',
      onCreate: onCreate,
      onEvict: onEvict,
    );
  }

  CollectionTrieNode<T>? read(String path) {
    return root.readCollection(path);
  }

  void add(String path) {
    root.addCollection(path);
  }

  void remove(String path) {
    return root.evictCollection(path);
  }
}

class CollectionTrieNode<T> {
  String collection;
  String path;
  T? item;
  Map<String, CollectionTrieNode<T>> children = {};
  CollectionTrieNode? parent;
  final T Function()? onCreate;
  final void Function(String path)? onEvict;

  CollectionTrieNode({
    required this.collection,
    required this.path,
    this.parent,
    this.onCreate,
    this.onEvict,
  });

  void seed() {
    item = onCreate?.call();
  }

  (String collection, String? subpath) _parsePath(String path) {
    final index = path.indexOf('/');

    if (index >= 0) {
      return (path.substring(0, index), path.substring(index + 1));
    }
    return (path, null);
  }

  void evict() {
    onEvict?.call("$path/$collection");
    children.keys.map((key) => children[key]!.evict());
  }

  void addCollection(String path) {
    final (collection, subPath) = _parsePath(path);

    CollectionTrieNode? child = children[collection];
    bool isNewChild = child == null;

    child ??= children[collection] = CollectionTrieNode(
      path: parent == null ? collection : "${parent!.path}/$collection",
      collection: collection,
      onEvict: onEvict,
      onCreate: onCreate,
    );

    // If this child node is the leaf node for this path and it did not previously
    // exist, then it should instantiate its initial data.
    if (subPath == null) {
      if (isNewChild) {
        child.seed();
      }
    } else {
      children[collection]!.addCollection(subPath);
    }
  }

  CollectionTrieNode<T>? readCollection(String path) {
    final (collection, subPath) = _parsePath(path);
    final child = children[collection];

    if (child != null) {
      if (subPath != null) {
        return child.readCollection(subPath);
      }
      return child;
    }

    return null;
  }

  void evictCollection(String path) {
    final (collection, subPath) = _parsePath(path);
    final child = children[collection];

    if (child != null) {
      if (subPath != null) {
        return child.evictCollection(subPath);
      }

      for (final child in children.values) {
        child.evict();
      }
    }
  }
}
