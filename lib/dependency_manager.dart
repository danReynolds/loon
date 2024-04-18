import 'package:loon/loon.dart';

class DependencyManager {
  /// Paths to documents and collections in the store can depend on each other.
  ///
  /// # Path dependencies
  ///
  /// final usersCollection = Loon.collection<TestUserModel>(
  ///   'posts',
  ///   dependenciesBuilder: (snap) {
  ///     return {
  ///       Loon.collection('users').doc(snap.data.userId),
  ///     };
  ///   },
  /// );
  ///
  /// In this example, a dependency is established between a post document and its associated user document.
  /// If the post's user is updated and broadcast to listeners, then the post should also be rebroadcast.
  ///
  /// This relationship is modeled using a dependents map:
  ///
  /// Dependents:
  /// {
  ///   users__1: Set(
  ///     posts__1
  ///   )
  /// }
  ///
  /// Now when users__1 is broadcast, it accesses its set of dependents and marks each of them for broadcast as well.
  /// Any observer of posts__1 or the posts collection will therefore be rebroadcast.
  ///
  /// # Deleting a path
  ///
  /// Deleting a path needs to be handled differently from updating a path.
  ///
  /// Let's take a more complicated example where a deep-path doc is dependent on another deep-path doc.
  /// In this example, say that post comments need to depend on a user's profile. So posts__1__comments__1 is
  /// dependent on users__1__profile__1. Now let's say that we delete the users collection. Since a parent path
  /// of users__1__profile__1 has been deleted users__1__profile__1 has been deleted too and posts__1__comments__1
  /// needs to be rebroadcast.
  ///
  /// The post comment isn't just dependent on the one document path, it is dependent on *every* parent node of its path as well.
  ///
  /// In addition to requiring a dependents map for handling path->path updates, supporting deletion of paths uses an additional dependency tree.
  /// Each path is modeled with its own dependency tree.
  ///
  /// So posts__1__comments__1 adds users__1__profile__1 to its path dependency tree, as well as the dependency tree of its parent collection.
  ///
  /// Now when the users collection is deleted, its path is broadcast with a [EventTypes.removed] event and each broadcast observer is iterated over to process
  /// the broadcast events. Each broadcast observer then iterates over the events and checks if any are for paths in its dependency tree.
  ///
  /// posts__1__comments__1 discovers the users path immediately in its dependency tree and rebroadcasts.
  ///
  /// This scales as O(n * m) where n = # of observers (small) and m = # of dependencies of each observer (small).

  final _dependentsStore = StoreNode<Set<Document>>();
  final _dependenciesStore = StoreNode<StoreNode<void>>();
}
