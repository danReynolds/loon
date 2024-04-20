import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';

void main() {
  group('Add dep', () {
    test('Correctly adds dependencies', () {
      final deps = DepTree();

      // Add a user as a dependency to a post.
      deps.addDep('posts__1', 'users__1');

      expect(deps.inspect(), {
        "posts": {
          // The user is stored as a dependency of both the posts document and its collection.
          "deps": {
            "users": {
              // The collection's dependency includes a ref count to the number of docs in the
              // collection that reference this dependency, so that it can know when it can be removed
              // from its collection-level dependencies.
              "1": 1,
            },
          },
          "1": {
            "deps": {
              "users": {
                "1": 1,
              },
            }
          }
        }
      });

      deps.addDep('posts__2', 'users__1');
      deps.addDep('posts__3', 'users__2');
      deps.addDep('posts__1__comments__2', 'users__2');

      expect(deps.inspect(), {
        "posts": {
          "deps": {
            "users": {
              // The posts collection should correctly increment the number of
              // references to the users__1 path.
              "1": 2,
              "2": 1,
            },
          },
          "1": {
            "deps": {
              "users": {
                "1": 1,
              },
            },
            "comments": {
              "deps": {
                "users": {
                  "2": 1,
                },
              },
              "2": {
                "deps": {
                  "users": {
                    "2": 1,
                  },
                },
              },
            },
          },
          "2": {
            "deps": {
              "users": {
                "1": 1,
              },
            }
          },
          "3": {
            "deps": {
              "users": {
                "2": 1,
              },
            }
          }
        }
      });
    });

    test('Correctly removes dependencies', () {
      final deps = DepTree();

      deps.addDep('posts__1', 'users__1');
      deps.addDep('posts__2', 'users__1');
      deps.addDep('posts__3', 'users__2');

      expect(deps.inspect(), {
        "posts": {
          "deps": {
            "users": {
              "1": 2,
              "2": 1,
            },
          },
          "1": {
            "deps": {
              "users": {
                "1": 1,
              },
            }
          },
          "2": {
            "deps": {
              "users": {
                "1": 1,
              },
            }
          },
          "3": {
            "deps": {
              "users": {
                "2": 1,
              },
            }
          }
        }
      });

      deps.removeDep('posts__1', 'users__1');

      expect(deps.inspect(), {
        "posts": {
          "deps": {
            "users": {
              // The posts collection's ref count for the users__1 dependency
              // has been decremented.
              "1": 1,
              "2": 1,
            },
          },
          // The posts__1 dependency has been removed.
          "2": {
            "deps": {
              "users": {
                "1": 1,
              },
            }
          },
          "3": {
            "deps": {
              "users": {
                "2": 1,
              },
            }
          }
        }
      });

      deps.removeDep('posts__2', 'users__1');

      expect(deps.inspect(), {
        "posts": {
          "deps": {
            "users": {
              // Now that the users__1 dependency has been decremented to 0,
              // it is removed from the posts collection's dependencies altogether.
              "2": 1,
            },
          },
          "3": {
            "deps": {
              "users": {
                "2": 1,
              },
            }
          }
        }
      });

      // As the last dependency of posts, removing the users__2 dependency should
      // recursively clear the dependency store.
      deps.removeDep('posts__3', 'users__2');

      expect(deps.inspect(), {});
    });

    test("Keeps paths with transient dependencies", () {
      final deps = DepTree();

      deps.addDep('posts__1', 'users__1');
      deps.addDep('posts__2', 'users__1');
      deps.addDep('posts__4__comments__2', 'users__2');

      expect(deps.inspect(), {
        "posts": {
          "deps": {
            "users": {
              "1": 2,
            },
          },
          "1": {
            "deps": {
              "users": {
                "1": 1,
              },
            }
          },
          "2": {
            "deps": {
              "users": {
                "1": 1,
              },
            }
          },
          "4": {
            "comments": {
              "deps": {
                "users": {
                  "2": 1,
                }
              },
              "2": {
                "deps": {
                  "users": {
                    "2": 1,
                  }
                }
              }
            }
          }
        }
      });

      deps.removeDep('posts__1', 'users__1');
      deps.removeDep('posts__2', 'users__1');

      expect(deps.inspect(), {
        // The posts collection should still exist since, while its deps were removed,
        // it has a transient path remaining to the remaining dependency of posts__4__collection__2.
        "posts": {
          "4": {
            "comments": {
              "deps": {
                "users": {
                  "2": 1,
                }
              },
              "2": {
                "deps": {
                  "users": {
                    "2": 1,
                  }
                }
              }
            }
          }
        }
      });

      deps.removeDep('posts__4__comments__2', 'users__2');

      // Removing the last remaining transient dependency should recursively clear the tree.
      expect(deps.inspect(), {});
    });
  });
}
