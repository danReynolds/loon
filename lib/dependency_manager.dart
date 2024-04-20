part of loon;

class DependencyManager {
  /// Paths to documents and collections in the store can depend on each other.
  ///
  /// # Document dependencies
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
  /// This relationship is modeled using a dependency tree.
  ///
  /// Dependencies:
  /// {
  ///   posts: {
  ///     dependencies: {
  ///       users: {
  ///         A: 2 -> ref count
  ///         B: 1
  ///       }
  ///     },
  ///     children: {
  ///       1: {
  ///         dependencies: {
  ///           users: {
  ///             A: 1
  ///           }
  ///         }
  ///       },
  ///       2: {
  ///         dependencies: {
  ///           users: {
  ///             A: 1
  ///           }
  ///         }
  ///       },
  ///       3: {
  ///         dependencies: {
  ///           users: {
  ///             B: 1
  ///           }
  ///         }
  ///       }
  ///     }
  ///   }
  /// }
  ///
  /// Suppose that there are three posts, two of which depend on user A and one dependent on user B.
  ///
  /// Broadcast events are stored by the [BroadcastManager] in a path tree structure as well, with each leaf node containing
  /// its associated broadcast [EventTypes].
  ///
  /// On broadcast, each broadcast observer is iterated over to process the tree of broadcast events. The observer of posts__1 traverses
  /// its dependency tree, checking to see if any of its dependencies have an event in the broadcast tree. It discovers users__A in the dependency
  /// tree and notifies its listeners.
  ///
  /// # Complexity
  ///
  /// The traversal of the posts__1 observer's dependency tree is O(n * m) where n is the number of dependencies in its tree and
  /// m is number of nodes in its path. Since documents should have a small number of dependencies and paths are short, this is efficient.
  ///
  /// The total complexity is then O(n * m * p) where p is the number of observers, which is also small since clients should only have a small
  /// number of active observers.
  ///
  /// # Deleting a path
  ///
  /// Let's take a more complicated example where a deep-path doc is dependent on another deep-path doc.
  /// In this example, say that post comments need to depend on a user's profile. So posts__A__comments__B is
  /// dependent on users__C__profile__D. Now let's say that we delete the users collection. Since a parent path
  /// of users__1__profile__1 has been deleted then users__1__profile__1 has been deleted too and posts__1__comments__1
  /// needs to be rebroadcast.
  ///
  /// The dependency graph looks like this:
  ///
  /// {
  ///   posts: {
  ///     A: {
  ///       comments: {
  ///         deps: {
  ///           users: {
  ///             C: {
  ///               profile: {
  ///                 D: 2 -> ref count
  ///               }
  ///             }
  ///           }
  ///         }
  ///         B: {
  ///           deps: {
  ///             users: {
  ///               C: {
  ///                 profile: {
  ///                   D: 1
  ///                 }
  ///               }
  ///             }
  ///           }
  ///         }
  ///       }
  ///     }
  ///   }
  /// }
  ///
  /// The post comment isn't just dependent on the one document path, it is dependent on every parent path of it as well.
  ///
  /// So posts__A__comments__B adds users__C__profile__D to its path dependency tree, as well as the dependency tree of its parent collection.
  ///
  /// Now when the users collection is deleted, its path is broadcast with a [EventTypes.removed] event and each broadcast observer is iterated over to process
  /// the broadcast events. A broadcast observer then iterates over its set of dependencies and checks if a partial path of any of its dependencies is present
  /// in the broadcast tree with a [EventTypes.removed] event.
  ///
  /// posts__A__comments__B discovers the users path immediately in the broadcast tree and rebroadcasts.
  ///
  /// The complexity of this operation is again O(n * m * p).

  final _dependenciesStore = StoreNode();
  final Map<Document, Set<Document>> _dependentsStore = {};

  /// Recalculates the set of dependencies of the updated document and updates them
  /// in the dependency store.
  void updateDependencies(Document doc) {
    final deps = doc.dependenciesBuilder?.call(doc.get()!);

    _dependenciesStore.write(doc.path, deps);
  }
}
