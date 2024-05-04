import 'package:flutter_test/flutter_test.dart';
import 'package:loon/store/resolver_store.dart';

void main() {
  group('Resolver store', () {
    group('write', () {
      test('Writes path values in the expected shape', () {
        final store = ResolverStore();

        store.write('users__1', 'users');
        store.write('users__2', 'users');
        store.write('users__2__messages__1', 'messages');

        expect(store.inspect(), {
          "users": {
            "__refs": {
              "users": 2,
              "messages": 1,
            },
            "2": {
              "messages": {
                "__refs": {
                  "messages": 1,
                }
              }
            }
          },
        });
      });
    });

    group('get', () {
      test("Returns the ref counts for the given collection path", () {
        final store = ResolverStore();

        store.write('users__1', 'users');
        store.write('users__2', 'users');
        store.write('users__2__messages__1', 'messages');

        expect(store.get('users'), {
          "users": 2,
          "messages": 1,
        });

        expect(store.get('users__2__messages'), {
          "messages": 1,
        });
      });
    });

    group('delete', () {
      test('Removes the ref counts from the parent ref nodes in the store', () {
        final store = ResolverStore();

        store.write('users__1', 'users');
        store.write('users__2', 'users');
        store.write('users__1__posts__1', 'posts');
        store.write('users__2__posts__3', 'posts');
        store.write('users__1__posts__1__reactions__1', 'reactions');
        store.write('users__1__posts__1__reactions__2', 'reactions');
        store.write('users__1__posts__2__reactions__3', 'reactions');
        store.write('users__1__posts__2__reactions__4', 'reactions');
        store.write('users__2__posts__3__reactions__5', 'reactions');

        expect(store.inspect(), {
          "users": {
            "__refs": {
              "users": 2,
              "posts": 2,
              "reactions": 5,
            },
            "1": {
              "posts": {
                "__refs": {
                  "posts": 1,
                  "reactions": 4,
                },
                "1": {
                  "reactions": {
                    "__refs": {
                      "reactions": 2,
                    }
                  }
                },
                "2": {
                  "reactions": {
                    "__refs": {
                      "reactions": 2,
                    }
                  }
                }
              }
            },
            "2": {
              "posts": {
                "__refs": {
                  "posts": 1,
                  "reactions": 1,
                },
                "3": {
                  "reactions": {
                    "__refs": {
                      "reactions": 1,
                    }
                  }
                }
              },
            }
          }
        });

        store.delete('users__1__posts__2__reactions');

        expect(store.inspect(), {
          "users": {
            "__refs": {
              "users": 2,
              "posts": 2,
              "reactions": 3,
            },
            "1": {
              "posts": {
                "__refs": {
                  "posts": 1,
                  "reactions": 2,
                },
                "1": {
                  "reactions": {
                    "__refs": {
                      "reactions": 2,
                    }
                  }
                },
              }
            },
            "2": {
              "posts": {
                "__refs": {
                  "posts": 1,
                  "reactions": 1,
                },
                "3": {
                  "reactions": {
                    "__refs": {
                      "reactions": 1,
                    }
                  }
                }
              },
            }
          }
        });

        store.delete('users__2__posts__3');

        expect(store.inspect(), {
          "users": {
            "__refs": {
              "users": 2,
              "posts": 2,
              "reactions": 2,
            },
            "1": {
              "posts": {
                "__refs": {
                  "posts": 1,
                  "reactions": 2,
                },
                "1": {
                  "reactions": {
                    "__refs": {
                      "reactions": 2,
                    }
                  }
                },
              }
            },
            "2": {
              "posts": {
                "__refs": {
                  "posts": 1,
                },
              },
            }
          }
        });

        store.delete('users__1__posts');

        expect(store.inspect(), {
          "users": {
            "__refs": {
              "users": 2,
              "posts": 1,
            },
            "2": {
              "posts": {
                "__refs": {
                  "posts": 1,
                },
              },
            }
          }
        });

        store.delete('users__2');

        expect(store.inspect(), {
          "users": {
            "__refs": {
              "users": 2,
            },
          }
        });

        store.delete('users');

        expect(store.inspect(), {});
      });
    });
  });
}
