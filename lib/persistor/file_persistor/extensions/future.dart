extension FutureExtensions<T> on Future<T> {
  Future<T?> catchType<S>() async {
    try {
      return await this;
    } catch (e) {
      if (e is S) {
        return null;
      }
      rethrow;
    }
  }
}
