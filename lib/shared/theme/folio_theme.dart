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
  static const warmAccent = Color(0xFFE7C768);
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
