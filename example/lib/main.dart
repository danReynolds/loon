import 'dart:async';

import 'package:example/models/user.dart';
import 'package:flutter/material.dart';
import 'package:loon/loon.dart';
import 'package:loon/persistor/file_persistor/debug_file_persistor.dart';
import 'package:loon/persistor/file_persistor/file_persistor.dart';
import 'package:uuid/uuid.dart';

const uuid = Uuid();

final _persistor = DebugFilePersistor();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  Loon.configure(persistor: _persistor);

  await Loon.hydrate();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
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
              actions: <Widget>[
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
              child: Row(
                children: [
                  Flexible(
                    flex: 8,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Users',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const Padding(padding: EdgeInsets.only(top: 16)),
                        QueryStreamBuilder<UserModel>(
                          query: UserModel.store.where(
                            (userSnap) =>
                                userSnap.data.name.startsWith(_controller.text),
                          ),
                          builder: (context, usersSnap) {
                            return ListView.builder(
                              shrinkWrap: true,
                              itemCount: usersSnap.length,
                              itemBuilder: (context, index) {
                                final userSnap = usersSnap[index];
                                final user = userSnap.data;

                                return Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(user.name),
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
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    flex: 2,
                    child: Container(
                      padding: const EdgeInsets.only(top: 16),
                      child: StreamBuilder<List<FileDataStore>>(
                        stream: _persistor.stream,
                        builder: (context, snap) {
                          if (!snap.hasData) {
                            return const CircularProgressIndicator();
                          }
                          final fileDataStores = snap.requireData;

                          return ListView.builder(
                            itemCount: fileDataStores.length,
                            itemBuilder: (context, index) {
                              final fileDataStore = fileDataStores[index];

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('File:'),
                                  const SizedBox(height: 8),
                                  Text(fileDataStore.name),
                                  const SizedBox(height: 8),
                                  const Text('Document count:'),
                                  const SizedBox(height: 8),
                                  Text(fileDataStore.data.values.length
                                      .toString()),
                                ],
                              );
                            },
                          );
                        },
                      ),
                    ),
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
          children: <Widget>[
            FloatingActionButton(
              onPressed: () {
                final id = uuid.v4();
                final doc = UserModel.store.doc(id);

                if (!doc.exists()) {
                  UserModel.store.doc(id).create(UserModel(name: 'User $id'));
                }
              },
              child: const Icon(Icons.add),
            ),
            const SizedBox(width: 24),
            FloatingActionButton(
              onPressed: () {
                UserModel.store.clear();
              },
              child: const Icon(Icons.delete),
            ),
          ],
        ),
      ),
    );
  }
}
