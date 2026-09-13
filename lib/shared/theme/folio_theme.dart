import 'package:flutter/widgets.dart';

abstract final class FolioColors {
  static const background = Color(0xFF0B0C0E);
  static const surface = Color(0xFF15171A);
  static const surfaceRaised = Color(0xFF1C1E21);
  static const textPrimary = Color(0xFFF4F3EF);
  static const textSecondary = Color(0xFFA7A6A1);
  static const textTertiary = Color(0xFF6F706D);
  static const separator = Color(0x1FFFFFFF);
  static const glassFill = Color(0x16F4F3EF);

  /// Cool neutral selection language. It deliberately avoids the previous
  /// yellow search treatment and the platform's purple selection handles.
  static const selection = Color(0x665F6B7C);
  static const selectionHandle = Color(0xFFC9D1DC);
  static const cursor = Color(0xFFE1E6ED);
  static const cursorBackground = Color(0xFF6E7888);
  static const searchMatch = Color(0x3D8C98A9);
  static const activeSearchMatch = Color(0xFFD7DEE8);
  static const activeSearchText = Color(0xFF161A20);
  static const pdfSearchMatch = Color(0x558C98A9);
  static const pdfActiveSearchMatch = Color(0xB8D7DEE8);
}

abstract final class FolioText {
  static const body = TextStyle(
    fontFamily: 'Inter',
    color: FolioColors.textPrimary,
    fontSize: 15,
    height: 1.35,
    fontWeight: FontWeight.w400,
  );

  static const title = TextStyle(
    fontFamily: 'Inter',
    color: FolioColors.textPrimary,
    fontSize: 34,
    height: 1.08,
    fontWeight: FontWeight.w600,
    letterSpacing: -1.1,
  );

  static const section = TextStyle(
    fontFamily: 'Inter',
    color: FolioColors.textSecondary,
    fontSize: 12,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.8,
  );

  static const filename = TextStyle(
    fontFamily: 'Inter',
    color: FolioColors.textPrimary,
    fontSize: 15.5,
    height: 1.25,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.1,
  );

  static const metadata = TextStyle(
    fontFamily: 'Inter',
    color: FolioColors.textSecondary,
    fontSize: 12.5,
    height: 1.2,
    fontWeight: FontWeight.w400,
  );
}
