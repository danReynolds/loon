import 'package:flutter_test/flutter_test.dart';
import 'package:loon/collection_trie.dart';

void main() {
  group("Collection Trie", () {
    test("Adds collection", () {
      final trie = CollectionTrie<Map>(
        onCreate: () {
          return {};
        },
      );

      trie.add('users/1/transactions/1');
      expect(trie.read('users/1/transactions/1')?.item, {});
    });
  });
}
