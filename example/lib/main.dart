import 'dart:async';
import 'package:example/models/user.dart';
import 'package:example/random_operation_runner.dart';
import 'package:flutter/material.dart';
import 'package:loon/loon.dart';
import 'package:uuid/uuid.dart';

const uuid = Uuid();

final logger = Logger('Playground');

void randomOperation() {}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  Loon.configure(
    persistor: Persistor.current(
      settings: const PersistorSettings(encrypted: true),
    ),
    enableLogging: true,
  );

  await logger.measure('Hydrate', () => Loon.hydrate());

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Loon Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Loon'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final _controller = TextEditingController();
  final _randomRunner = RandomOperationRunner();

  @override
  initState() {
    super.initState();
    _controller.addListener(() {
      setState(() {});
    });
  }

  Future<void> _showEditDialog(Document<UserModel> doc) async {
    final initialUser = doc.get()!;

    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return DocumentStreamBuilder(
          doc: doc,
          builder: (context, userSnap) {
            final user = userSnap!.data;

            return AlertDialog(
              title: const Text('Edit name'),
              content: TextFormField(
                initialValue: user.name,
                onChanged: (updatedName) {
                  userSnap.doc.update(
                    user.copyWith(name: updatedName),
                  );
                },
              ),
              actions: [
                TextButton(
                  child: const Text('Cancel'),
                  onPressed: () {
                    doc.update(initialUser.data);
                    Navigator.of(context).pop();
                  },
                ),
                TextButton(
                  child: const Text('Done'),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          children: [
            SizedBox(
              width: 300,
              child: TextField(
                controller: _controller,
                decoration: const InputDecoration(hintText: 'Search users'),
              ),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  QueryStreamBuilder(
                    query: UserModel.store.where(
                      (usersSnap) =>
                          usersSnap.data.name.startsWith(_controller.text),
                    ),
                    builder: (context, usersSnap) {
                      return Flexible(
                        child: Column(
                          children: [
                            Text(
                              '${usersSnap.length} Users',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const Padding(padding: EdgeInsets.only(top: 16)),
                            Flexible(
                              child: ListView.builder(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                shrinkWrap: true,
                                itemCount: usersSnap.length,
                                itemBuilder: (context, index) {
                                  final userSnap = usersSnap[index];
                                  final user = userSnap.data;

                                  return Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Flexible(child: Text(user.name)),
                                      TextButton(
                                        onPressed: () {
                                          _showEditDialog(userSnap.doc);
                                        },
                                        child: const Text('Edit'),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          UserModel.store
                                              .doc(userSnap.id)
                                              .delete();
                                        },
                                        child: Text(
                                          'Remove',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium!
                                              .copyWith(
                                                color: Colors.red,
                                              ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: Container(
        padding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            FloatingActionButton(
              onPressed: () {
                final id = uuid.v4();
                UserModel.store.doc(id).create(UserModel(name: 'User $id'));
              },
              child: const Icon(Icons.add),
            ),
            const SizedBox(width: 24),
            FloatingActionButton.extended(
              label: const Text('Load test (10000)'),
              onPressed: () {
                for (int i = 0; i < 10000; i++) {
                  final id = uuid.v4();
                  UserModel.store.doc(id).create(UserModel(name: 'User $id'));
                }
              },
            ),
            const SizedBox(width: 24),
            FloatingActionButton(
              onPressed: () {
                Loon.clearAll();
              },
              child: const Icon(Icons.delete),
            ),
            const SizedBox(width: 24),
            FloatingActionButton(
              onPressed: () {
                if (_randomRunner.isRunning) {
                  _randomRunner.stop();
                } else {
                  _randomRunner.run();
                }
                setState(() {});
              },
              child:
                  Icon(_randomRunner.isRunning ? Icons.stop : Icons.play_arrow),
            ),
          ],
        ),
      ),
    );
  }
}
