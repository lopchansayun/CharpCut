import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Editor (dark) palette
// ---------------------------------------------------------------------------
const editorBg = Color(0xFF131314);
const editorSurface = Color(0xFF232325);
const editorSurfaceHigh = Color(0xFF2D2D30);
const editorMuted = Color(0xFF8C8C91);
const accentCyan = Color(0xFF1ACBE0);
const selectionTeal = Color(0xFF1E8E9B);
const accentBlue = Color(0xFF2F7BFF);

// ---------------------------------------------------------------------------
// Home (light) palette
// ---------------------------------------------------------------------------
const homeBlue = Color(0xFF1F63E8);
const homeCard = Color(0xFFD9E8FF);
const homeInk = Color(0xFF111114);
const homeMuted = Color(0xFFA7AEBB);

// ---------------------------------------------------------------------------
// Export-done palette
// ---------------------------------------------------------------------------
const doneBg = Color(0xFF335B6A);
const doneCard = Color(0xFF3F6978);
const doneTile = Color(0xFF3A6473);

SnackBarThemeData _snackTheme() => SnackBarThemeData(
  backgroundColor: const Color(0xFF2D2D30),
  contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
  behavior: SnackBarBehavior.floating,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
);

ThemeData buildDarkTheme() => ThemeData(
  brightness: Brightness.dark,
  useMaterial3: true,
  scaffoldBackgroundColor: editorBg,
  colorScheme: const ColorScheme.dark(
    primary: accentCyan,
    onPrimary: Colors.black,
    secondary: accentCyan,
    surface: editorSurface,
    onSurface: Colors.white,
  ),
  iconTheme: const IconThemeData(color: Colors.white),
  iconButtonTheme: IconButtonThemeData(
    style: ButtonStyle(
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled) ? const Color(0xFF5A5A5E) : Colors.white,
      ),
    ),
  ),
  snackBarTheme: _snackTheme(),
  splashFactory: NoSplash.splashFactory,
  highlightColor: Colors.transparent,
);

ThemeData buildLightTheme() => ThemeData(
  brightness: Brightness.light,
  useMaterial3: true,
  scaffoldBackgroundColor: Colors.white,
  colorScheme: ColorScheme.fromSeed(seedColor: homeBlue, brightness: Brightness.light),
  snackBarTheme: _snackTheme(),
  splashFactory: NoSplash.splashFactory,
  highlightColor: Colors.transparent,
);

/// Shows a short floating message. [bottomInset] lifts it clear of a bottom bar
/// so the message never covers controls the user may want to tap next.
void toast(BuildContext context, String value, {double bottomInset = 0}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(value),
      duration: const Duration(milliseconds: 1400),
      behavior: SnackBarBehavior.floating,
      margin: bottomInset > 0 ? EdgeInsets.fromLTRB(16, 0, 16, bottomInset) : null,
    ));
}

/// 00:00 style timestamp (whole seconds, floored).
String formatClock(double seconds) {
  final total = seconds.isNaN || seconds < 0 ? 0 : seconds.floor();
  final m = (total ~/ 60).toString().padLeft(2, '0');
  final s = (total % 60).toString().padLeft(2, '0');
  return '$m:$s';
}
