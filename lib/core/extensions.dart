import 'dart:math';

extension ListExt<T> on List<T> {
  T get random {
    Random random = Random();
    return elementAt(random.nextInt(length));
  }
}
