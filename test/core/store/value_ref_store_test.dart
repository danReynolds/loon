import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';

const _d = '__';
const _alphabet = ['a', 'b', 'c'];

/// A random path of 1 to 3 segments over a small alphabet, so that paths collide and share
/// prefixes, which is where the tree-restructuring edge cases live.
String _randomPath(Random r) {
  final depth = 1 + r.nextInt(3);
  return List.generate(depth, (_) => _alphabet[r.nextInt(_alphabet.length)])
      .join(_d);
}

/// All non-empty paths of depth 1 and 2: a fixed grid of query points.
final _grid = <String>[
  for (final a in _alphabet) ...[
    a,
    for (final b in _alphabet) '$a$_d$b',
  ],
];

/// Whether [key] is at or below [path] in the tree.
bool _atOrUnder(String key, String path) =>
    path.isEmpty || key == path || key.startsWith('$path$_d');

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
                      },
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
                      },
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
                      },
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
                      },
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
                      },
                    },
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
                      },
                    },
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
            'Decrements parent refs',
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
                        },
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
                        },
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
                    'test': 1,
                    'test2': 1,
                    'User 1': 1,
                  },
                  "users": {
                    "__refs": {
                      'test': 1,
                      'test2': 1,
                      'User 1': 1,
                    },
                    "__values": {
                      "1": "User 1",
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
                        },
                      }
                    }
                  }
                },
              );

              store.delete('users__1', recursive: false);

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
                        },
                      }
                    }
                  }
                },
              );

              store.delete('users__1__friends__1');

              expect(
                store.inspect(),
                {
                  "__refs": {
                    'test2': 1,
                  },
                  "users": {
                    "__refs": {
                      'test2': 1,
                    },
                    "1": {
                      "__refs": {
                        'test2': 1,
                      },
                      "friends": {
                        "__refs": {
                          'test2': 1,
                        },
                        "__values": {
                          "2": 'test2',
                        },
                      }
                    }
                  }
                },
              );

              // No-op since the path `users__1__friends__3` does not exist in the store.
              store.delete('users__1__friends__3');

              expect(
                store.inspect(),
                {
                  "__refs": {
                    'test2': 1,
                  },
                  "users": {
                    "__refs": {
                      'test2': 1,
                    },
                    "1": {
                      "__refs": {
                        'test2': 1,
                      },
                      "friends": {
                        "__refs": {
                          'test2': 1,
                        },
                        "__values": {
                          "2": 'test2',
                        },
                      }
                    }
                  }
                },
              );

              store.delete('users__1__friends');

              expect(store.inspect(), {});
            },
          );
        },
      );

      group('getRefs', () {
        test(
          'Returns the refs under the given path',
          () {
            final store = ValueRefStore();

            store.write('users__1', 'Dan');
            store.write('users__1__friends__1', 'Nik');
            store.write('users__1__friends__2', 'Dan');

            expect(
              store.getRefs(),
              {'Dan': 2, 'Nik': 1},
            );

            expect(
              store.getRefs(ValueStore.root),
              {'Dan': 2, 'Nik': 1},
            );

            expect(
              store.getRefs('users'),
              {'Dan': 2, 'Nik': 1},
            );

            expect(
              store.getRefs('users__1'),
              {'Dan': 1, 'Nik': 1},
            );

            expect(
              store.getRefs('users__1__friends'),
              {'Dan': 1, 'Nik': 1},
            );

            expect(
              store.getRefs('users__1__friends__1'),
              null,
            );
          },
        );
      });

      group('property', () {
        // Random write/delete sequences are checked against a flat map used as an
        // independent oracle for the ref aggregation in each subtree.
        test(
            'Aggregates refs matching the values in each subtree across random writes and deletes',
            () {
          for (var seed = 0; seed < 50; seed++) {
            final r = Random(seed);
            final store = ValueRefStore<String>();
            final model = <String, String>{};
            final ops = <String>[];

            // getRefs(path) aggregates values strictly under a node; for the root path it
            // aggregates every value in the store.
            Map<String, int> refsUnder(String path) {
              final counts = <String, int>{};
              for (final entry in model.entries) {
                final under =
                    path.isEmpty ? true : entry.key.startsWith('$path$_d');
                if (under) {
                  counts[entry.value] = (counts[entry.value] ?? 0) + 1;
                }
              }
              return counts;
            }

            for (var step = 0; step < 50; step++) {
              if (r.nextInt(3) != 0) {
                final p = _randomPath(r);
                // A small value space produces many shared refs.
                final v = _alphabet[r.nextInt(_alphabet.length)];
                store.write(p, v);
                model[p] = v;
                ops.add('write($p,$v)');
              } else {
                final p = _randomPath(r);
                store.delete(p);
                model.removeWhere((k, _) => _atOrUnder(k, p));
                ops.add('delete($p)');
              }

              final reason = 'seed=$seed ops=$ops';
              for (final q in ['', ..._grid]) {
                final expected = refsUnder(q);
                final actual = store.getRefs(q) ?? const <String, int>{};
                expect(Map<String, int>.from(actual), equals(expected),
                    reason: '$reason getRefs("$q")');
                expect(store.extractValues(q), equals(expected.keys.toSet()),
                    reason: '$reason extractValues("$q")');
              }
            }
          }
        });
      });
    },
  );
}
