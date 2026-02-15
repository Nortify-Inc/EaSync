import 'handler.dart';

class EaColor {
  // Accent (soft blue)
  static const Color fore = Color.fromARGB(255, 103, 117, 199);
  static const Color secondaryFore = Color(0xFF9AAEFF);

  // Surfaces
  static const Color back = Color.fromARGB(255, 32, 32, 32);
  static const Color secondaryBack = Color(0xFF2A2A2D);

  // Main background
  static const Color background = Color.fromARGB(255, 9, 9, 17);

  // Text
  static const Color textPrimary = Color(0xFFEDEDED);
  static const Color textSecondary = Color(0xFF9A9AA0);
  static const Color textDisabled = Color(0xFF6B6B70);

  // Border
  static const Color border = Color(0xFF2F2F34);
}

class EaText {
  static final TextStyle primary = GoogleFonts.poppins(
    color: EaColor.textPrimary,
    fontSize: 20,
    fontWeight: FontWeight.w600,
  );

  static final TextStyle primaryTranslucent = GoogleFonts.poppins(
    color: EaColor.textSecondary,
    fontSize: 16,
  );

  static final TextStyle primaryBack = GoogleFonts.poppins(
    color: Colors.white,
    fontSize: 15,
    fontWeight: FontWeight.w500,
  );

  static final TextStyle secondary = GoogleFonts.poppins(
    color: EaColor.textSecondary,
    fontSize: 14,
  );

  static final TextStyle secondaryTranslucent = GoogleFonts.poppins(
    color: EaColor.textSecondary.withValues(alpha: 0.5),
    fontSize: 14,
  );

  static final TextStyle secondaryBack = GoogleFonts.poppins(
    color: EaColor.textSecondary,
    fontStyle: FontStyle.italic,
    fontSize: 12,
    fontWeight: FontWeight.w300,
  );

  static final TextStyle accent = GoogleFonts.poppins(
    color: EaColor.fore,
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );

  static final TextStyle small = GoogleFonts.poppins(
    color: EaColor.textSecondary,
    fontSize: 12,
  );
}
