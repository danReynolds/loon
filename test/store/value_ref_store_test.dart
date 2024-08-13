import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';

void main() {
  group(
    'ValueRefStore',
    () {
      group('write', () {
        test(
          'Writes values into the store with the correct ref count',
          () {
            final store = ValueRefStore();
            store.write('users__1__friends__1', 'test');

            expect(
              store.inspect(),
              {
                "__refs": {
                  'test': 1,
                },
                "users": {
                  "__refs": {
                    'test': 1,
                  },
                  "1": {
                    "__refs": {
                      'test': 1,
                    },
                    "friends": {
                      "__refs": {
                        'test': 1,
                      },
                      "__values": {
                        "1": 'test',
                      }
                    }
                  }
                }
              },
            );

            store.write('users__1__friends__2', 'test');
            store.write('users__1__friends__3', 'test2');

            expect(
              store.inspect(),
              {
                "__refs": {
                  'test': 2,
                  'test2': 1,
                },
                "users": {
                  "__refs": {
                    'test': 2,
                    'test2': 1,
                  },
                  "1": {
                    "__refs": {
                      'test': 2,
                      'test2': 1,
                    },
                    "friends": {
                      "__refs": {
                        'test': 2,
                        'test2': 1,
                      },
                      "__values": {
                        "1": 'test',
                        "2": 'test',
                        "3": 'test2',
                      }
                    }
                  }
                }
              },
            );

            store.write('users__1', 'User 1');

            expect(
              store.inspect(),
              {
                "__refs": {
                  'test': 2,
                  'test2': 1,
                  'User 1': 1,
                },
                "users": {
                  "__refs": {
                    'test': 2,
                    'test2': 1,
                    'User 1': 1,
                  },
                  "__values": {
                    "1": 'User 1',
                  },
                  "1": {
                    "__refs": {
                      'test': 2,
                      'test2': 1,
                    },
                    "friends": {
                      "__refs": {
                        'test': 2,
                        'test2': 1,
                      },
                      "__values": {
                        "1": 'test',
                        "2": 'test',
                        "3": 'test2',
                      }
                    }
                  }
                }
              },
            );

            // The ref count should not be incremented when writing a duplicate value.
            store.write('users__1__friends__1', 'test');

            expect(
              store.inspect(),
              {
                "__refs": {
                  'test': 2,
                  'test2': 1,
                  'User 1': 1,
                },
                "users": {
                  "__refs": {
                    'test': 2,
                    'test2': 1,
                    'User 1': 1,
                  },
                  "__values": {
                    "1": 'User 1',
                  },
                  "1": {
                    "__refs": {
                      'test': 2,
                      'test2': 1,
                    },
                    "friends": {
                      "__refs": {
                        'test': 2,
                        'test2': 1,
                      },
                      "__values": {
                        "1": 'test',
                        "2": 'test',
                        "3": 'test2',
                      }
                    }
                  }
                }
              },
            );

            // The ref count should be incremented for the new value and decremented for the previous value.
            store.write('users__1__friends__1', 'test2');

            expect(
              store.inspect(),
              {
                "__refs": {
                  'test': 1,
                  'test2': 2,
                  'User 1': 1,
                },
                "users": {
                  "__refs": {
                    'test': 1,
                    'test2': 2,
                    'User 1': 1,
                  },
                  "__values": {
                    "1": 'User 1',
                  },
                  "1": {
                    "__refs": {
                      'test': 1,
                      'test2': 2,
                    },
                    "friends": {
                      "__refs": {
                        'test': 1,
                        'test2': 2,
                      },
                      "__values": {
                        "1": 'test2',
                        "2": 'test',
                        "3": 'test2',
                      }
                    }
                  }
                }
              },
            );

            store.write('', '__root__');

            expect(
              store.inspect(),
              {
                "__refs": {
                  'test': 1,
                  'test2': 2,
                  'User 1': 1,
                  '__root__': 1,
                },
                "__values": {
                  "": '__root__',
                },
                "users": {
                  "__refs": {
                    'test': 1,
                    'test2': 2,
                    'User 1': 1,
                  },
                  "__values": {
                    "1": 'User 1',
                  },
                  "1": {
                    "__refs": {
                      'test': 1,
                      'test2': 2,
                    },
                    "friends": {
                      "__refs": {
                        'test': 1,
                        'test2': 2,
                      },
                      "__values": {
                        "1": 'test2',
                        "2": 'test',
                        "3": 'test2',
                      }
                    }
                  }
                }
              },
            );
          },
        );
      });

      group(
        'delete',
        () {
          test(
            'Decrements parent refs by all child refs',
            () {
              final store = ValueRefStore();

              store.write('users__1__friends__1', 'test');
              store.write('users__1__friends__2', 'test2');
              store.write('users__1__friends__3', 'test3');

              expect(
                store.inspect(),
                {
                  "__refs": {
                    'test': 1,
                    'test2': 1,
                    'test3': 1,
                  },
                  "users": {
                    "__refs": {
                      'test': 1,
                      'test2': 1,
                      'test3': 1,
                    },
                    "1": {
                      "__refs": {
                        'test': 1,
                        'test2': 1,
                        'test3': 1,
                      },
                      "friends": {
                        "__refs": {
                          'test': 1,
                          'test2': 1,
                          'test3': 1,
                        },
                        "__values": {
                          "1": 'test',
                          "2": 'test2',
                          "3": 'test3',
                        }
                      }
                    }
                  }
                },
              );

              store.delete('users__1__friends__3');

              expect(
                store.inspect(),
                {
                  "__refs": {
                    'test': 1,
                    'test2': 1,
                  },
                  "users": {
                    "__refs": {
                      'test': 1,
                      'test2': 1,
                    },
                    "1": {
                      "__refs": {
                        'test': 1,
                        'test2': 1,
                      },
                      "friends": {
                        "__refs": {
                          'test': 1,
                          'test2': 1,
                        },
                        "__values": {
                          "1": 'test',
                          "2": 'test2',
                        }
                      }
                    }
                  }
                },
              );

              store.write('users__1', 'User 1');
              store.delete('users__1__friends');

              expect(
                store.inspect(),
                {
                  "__refs": {
                    'User 1': 1,
                  },
                  "users": {
                    "__refs": {
                      'User 1': 1,
                    },
                    "__values": {
                      "1": "User 1",
                    },
                  }
                },
              );

              store.delete('users__1');

              expect(store.inspect(), {});
            },
          );
        },
      );

      group(
        'get',
        () {
          test(
            'Returns the value at the given path',
            () {
              final store = ValueRefStore();

              store.write('users__1__friends__1', 'test');

              expect(store.get('users__1__friends__1'), 'test');
              expect(store.get('users__1__friends__2'), null);
              expect(store.get('users__1__friends'), null);
            },
          );
        },
      );

      group(
        'getSubpathValues',
        () {
          test(
            'Returns all values along the given path',
            () {
              final store = ValueRefStore();

              store.write('users__1', 1);
              store.write('users__1__friends__2', 2);

              expect(store.getSubpathValues('users__1'), [1]);
              expect(store.getSubpathValues('users__1__friends__2'), [1, 2]);
            },
          );
        },
      );
    },
  );
}
