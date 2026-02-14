import 'handler.dart';

class EaColor {
  static const Color fore = Color.fromARGB(255, 31, 35, 58);
  static const Color secondaryFore = Color.fromARGB(255, 52, 64, 133);
  static const Color back = Color.fromARGB(255, 206, 206, 206);
  static const Color secondaryBack = Color.fromARGB(255, 255, 255, 255);
}

class EaText {
  static final TextStyle primary = GoogleFonts.poppins(
    color: EaColor.fore,
    fontSize: 16,
    fontWeight: FontWeight.w500,
  );

  static final TextStyle primaryTranslucent = GoogleFonts.poppins(
    color: EaColor.fore.withValues(alpha: 0.4),
    fontSize: 16,
    fontWeight: FontWeight.w500,
  );

  static final TextStyle primaryBack = GoogleFonts.poppins(
    color: EaColor.back,
    fontSize: 16,
    fontWeight: FontWeight.w500,
  );

  static final TextStyle secondary = GoogleFonts.poppins(
    color: EaColor.fore,
    fontSize: 14,
    fontWeight: FontWeight.w400,
  );

  static final TextStyle secondaryTranslucent = GoogleFonts.poppins(
    color: EaColor.fore.withValues(alpha: 0.5),
    fontSize: 14,
    fontWeight: FontWeight.w400,
  );

  static final TextStyle secondaryBack = GoogleFonts.poppins(
    color: EaColor.back,
    fontSize: 14,
    fontWeight: FontWeight.w400,
  );
}
