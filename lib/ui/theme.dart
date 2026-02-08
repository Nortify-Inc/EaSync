import 'handler.dart';

class EaColor {
  static const Color fore = Color.fromARGB(255, 159, 159, 159);
  static const Color back = Color.fromARGB(255, 46, 45, 50);

  // Secondary colors
  static const Color secondaryFore = Color.fromARGB(255, 200, 200, 220);
  static const Color secondaryBack = Color.fromARGB(255, 70, 65, 90);
}

class EaText {
  static const TextStyle primary = TextStyle(
    color: Color.fromARGB(255, 255, 255, 255),
    fontSize: 16,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle secondary = TextStyle(
    color: EaColor.secondaryFore,
    fontSize: 14,
    fontWeight: FontWeight.w400,
  );
}
