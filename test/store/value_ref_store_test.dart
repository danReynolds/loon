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
                      },
                      "1": {
                        "__refs": {
                          "test": 1,
                        }
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
                      },
                      "1": {
                        "__refs": {
                          "test": 1,
                        }
                      },
                      "2": {
                        "__refs": {
                          "test": 1,
                        }
                      },
                      "3": {
                        "__refs": {
                          "test2": 1,
                        }
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
                      'User 1': 1,
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
                      "1": {
                        "__refs": {
                          "test": 1,
                        }
                      },
                      "2": {
                        "__refs": {
                          "test": 1,
                        }
                      },
                      "3": {
                        "__refs": {
                          "test2": 1,
                        }
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
                      'User 1': 1,
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
                      "1": {
                        "__refs": {
                          "test": 1,
                        }
                      },
                      "2": {
                        "__refs": {
                          "test": 1,
                        }
                      },
                      "3": {
                        "__refs": {
                          "test2": 1,
                        }
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
                      'User 1': 1,
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
                      "1": {
                        "__refs": {
                          "test2": 1,
                        }
                      },
                      "2": {
                        "__refs": {
                          "test": 1,
                        }
                      },
                      "3": {
                        "__refs": {
                          "test2": 1,
                        }
                      }
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
                "": {
                  "__refs": {
                    "__root__": 1,
                  }
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
                      'User 1': 1,
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
                      "1": {
                        "__refs": {
                          "test2": 1,
                        }
                      },
                      "2": {
                        "__refs": {
                          "test": 1,
                        }
                      },
                      "3": {
                        "__refs": {
                          "test2": 1,
                        }
                      }
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
                        "1": {
                          "__refs": {
                            "test": 1,
                          }
                        },
                        "2": {
                          "__refs": {
                            "test2": 1,
                          },
                        },
                        "3": {
                          "__refs": {
                            "test3": 1,
                          },
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
                        },
                        "1": {
                          "__refs": {
                            "test": 1,
                          }
                        },
                        "2": {
                          "__refs": {
                            "test2": 1,
                          },
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
                        'User 1': 1,
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
                        "1": {
                          "__refs": {
                            "test": 1,
                          }
                        },
                        "2": {
                          "__refs": {
                            "test2": 1,
                          },
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
                        "1": {
                          "__refs": {
                            "test": 1,
                          }
                        },
                        "2": {
                          "__refs": {
                            "test2": 1,
                          },
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
    },
  );
}
