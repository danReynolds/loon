part of 'loon.dart';

abstract interface class Computable<T> {
  T get();
  Stream<T> stream();
}
