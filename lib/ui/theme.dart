import 'handler.dart';

class EaColor {
  static const Color fore = Color.fromARGB(255, 31, 35, 58);
  static const Color secondaryFore = Color.fromARGB(255, 52, 64, 133);
  static const Color back = Color.fromARGB(255, 206, 206, 206);
  static const Color secondaryBack = Color.fromARGB(255, 255, 255, 255);
}

class EaText {
  static const TextStyle primary = TextStyle(
    color: EaColor.fore,
    fontSize: 16,
    fontWeight: FontWeight.w500,
  );

  static final TextStyle primaryTranslucent = TextStyle(
    color: EaColor.fore.withValues(alpha: 0.4),
    fontSize: 16,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle primaryBack = TextStyle(
    color: EaColor.back,
    fontSize: 16,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle secondary = TextStyle(
    color: EaColor.fore,
    fontSize: 14,
    fontWeight: FontWeight.w400,
  );

  static final TextStyle secondaryTranslucent = TextStyle(
    color: EaColor.fore.withValues(alpha: 0.5),
    fontSize: 14,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle secondaryBack = TextStyle(
    color: EaColor.back,
    fontSize: 14,
    fontWeight: FontWeight.w400,
  );
}
