extension MapExtensions on Map {
  void deepAssign(List<String> keys, value) {
    var current = this;

    for (int i = 0; i < keys.length; i++) {
      final key = keys[i];

      if (i == keys.length - 1) {
        current[key] = value;
      } else {
        if (!current.containsKey(key)) {
          current[key] = {};
        }
        current = current[key];
      }
    }
  }
}
