Persistence arch:

By default, each top-level collection gets its own data store.

```dart
// users.json
{
  users: {
    __values: {
      1: UserModel(),
      2: UserModel(),
    },
  },
  users__1: {
    posts: {
      __values: {
        1: PostModel(),
        2: PostModel(),
      }
    }
  },
}
```

Here, the top-level `users` collection gets its own data store and all data for the user is stored under it. If you wanted to store deeper collections separately, you can specify a `persistenceKey` on the deeper collection like `posts` which breaks it out into its own data store:


```dart
final userCollection = Loon.collection('users').subcollection(
  'posts',
  persistorSettings: (snap) {
    return 'posts';
  }
);
```

Now all of a user's posts across the different users collections are grouped into a global posts data store as shown below:

```dart
// posts.json
{
  users: {
    1: {
        posts: {
          __values: {
            1: PostModel(),
            2: PostModel(),
          }
        }
      },
    2: {
      posts: {
        __values: {
          3: PostModel(),
          4: PostModel(),
        }
      }
    },
  }
}
```

If the users collection was removed, then we would need to know which file data stores contain users or collections under users.

This requires an in-memory index that maps collections to data stores:

```dart
{
  users: {
    1: {
      posts: {
        __refs: {
          // Maintains a ref count so that it knows when the data store can be removed from the index 
          FileDataStore('posts'): 2,
          FileDataStore('posts_shard_1'): 1,
        }
        1: FileDataStore('posts'),
        2: FileDataStore('posts'),
        3: FileDataStore('posts_shard_1'),
      }
    }
  }
}
```

If after writing/deleting a document from the above ref value store, the document's data store is no longer referenced by the collection, then it can be removed from the accompanying value store below:

```dart
users: {
  1: {
    posts: ['posts', 'posts_shard_1'],
  }
}
```

so that on hydration, we read the index and then find the collections being hydrated and hydrate their associated file data stores.
