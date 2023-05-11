import 'package:example/models/user.dart';
import 'package:flutter/material.dart';
import 'package:loon/loon.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  Loon.configure(persistor: FilePersistor());

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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
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
  int _userCount = 0;

  Future<void> _showEditDialog(DocumentSnapshot<UserModel> userSnap) async {
    final controller = TextEditingController();
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Edit name'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: 'Enter name here'),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Save'),
              onPressed: () {
                userSnap.doc.update(
                  userSnap.data.copyWith(name: controller.text),
                );
                Navigator.of(context).pop();
              },
            ),
          ],
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
        child: StreamQueryBuilder<UserModel>(
          query: UserModel.store.where(
            (userSnap) => userSnap.data.name.startsWith('User'),
          ),
          builder: (context, usersSnap) {
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Users', style: Theme.of(context).textTheme.headlineSmall),
                const Padding(padding: EdgeInsets.only(top: 16)),
                ListView.builder(
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
                            _showEditDialog(userSnap);
                          },
                          child: const Text('Edit'),
                        ),
                        TextButton(
                          onPressed: () {
                            UserModel.store.delete(userSnap.id);
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
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () {
          final id = _userCount.toString();
          final doc = UserModel.store.doc(id);

          if (!doc.exists()) {
            UserModel.store.doc(id).create(UserModel(name: 'User $_userCount'));
          }
          _userCount++;
        },
      ),
    );
  }
}
