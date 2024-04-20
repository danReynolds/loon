import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';

void main() {
  group('write', () {
    test('Correctly writes values', () {
      final store = ValueStore<String>();

      store.write('users__1', 'Dan');
      store.write('users__2', 'Sonja');
      store.write('users__1__messages__2', 'Hey there!');

      expect(store.inspect(), {
        "users": {
          "__values": {
            "1": "Dan",
            "2": "Sonja",
          },
          "1": {
            "messages": {
              "__values": {
                "2": "Hey there!",
              },
            },
          },
        }
      });
    });
  });

  group('get', () {
    test('Retrieves values', () {
      final store = ValueStore<String>();

      store.write('users__1', 'Dan');
      store.write('users__2', 'Sonja');
      store.write('users__1__friends__1', 'Nik');

      expect(store.get('users__1'), 'Dan');
      expect(store.get('users__1__friends__1'), 'Nik');
      expect(store.getAll('users'), {
        "1": "Dan",
        "2": "Sonja",
      });
    });
  });
}
