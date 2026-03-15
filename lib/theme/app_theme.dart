import 'package:flutter/material.dart';

/// Shared colour tokens used across DetectionScreen, _PingGpsBadge,
/// and any other widget that needs the detection-UI palette.
class AppColors {
  static const Color accentGreen = Color(0xFF00E676);
  static const Color accentAmber = Color(0xFFFFD740);
  static const Color accentRed = Color(0xFFFF5252);
  static const Color accentCyan = Color(0xFF00B0FF);

  /// 90 % opaque dark panel background.
  static const Color panelBg = Color(0xE6121212);
}

class AppTheme {
  // Use a dark-themed UI (background: #0A0A0A)
  static const Color background = Color(0xFF0A0A0A);

  // Top bar and bottom sheet components backgrounds
  static const Color panelBackground = Color(0xFF1A1A1A);

  // Overlay/transparent styles
  static const Color transparentWhite15 = Color(
    0x26FFFFFF,
  ); // 15% opacity white
  static const Color transparentWhite40 = Color(
    0x66FFFFFF,
  ); // 40% opacity white
  static const Color transparentWhite50 = Color(
    0x80FFFFFF,
  ); // 50% opacity white

  // Brand colors
  static const Color scanningGreen = Color(0xFF00FF00); // Pulsing green dot
  static const Color primaryWhite = Colors.white;

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: scanningGreen,
      colorScheme: const ColorScheme.dark(
        surface: panelBackground,
        primary: scanningGreen,
      ),
      iconTheme: const IconThemeData(color: primaryWhite),
    );
  }
}
