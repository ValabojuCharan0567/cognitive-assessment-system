class DifficultyController {
  int level = 0;

  void increase() {
    if (level < 2) level++;
  }

  void decrease() {
    if (level > 0) level--;
  }
}
