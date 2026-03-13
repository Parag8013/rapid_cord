import 'package:flutter/material.dart';

/// RapidCord color palette — matches the warm purple-burgundy gradient
/// from the Discord screenshot with reddish-purple undertones.
class AppColors {
  AppColors._();

  // ── Background Gradients (vivid purple → deep violet → near-black) ──
  static const Color gradientStart = Color(0xFF3D1878); // vivid violet-purple
  static const Color gradientMid = Color(0xFF1E0B4A); // deep indigo-purple
  static const Color gradientEnd = Color(0xFF0D0626); // near-black with purple

  // ── Surface Colors ──
  static const Color serverBar = Color(0xFF100620); // darkest sidebar
  static const Color sidebarBg = Color(0xFF1A0C34); // sidebar background
  static const Color channelActive = Color(0xFF341860); // selected channel
  static const Color channelHover = Color(0xFF271450); // hovered channel
  static const Color contentBg = Color(0xFF160A2C); // main content area
  static const Color inputBg = Color(0xFF261440); // input field bg
  static const Color cardBg = Color(0xFF20104A); // card/embed bg

  // ── Accent ──
  static const Color purple = Color(0xFF8B6FFF);
  static const Color purpleLight = Color(0xFFAA94FF);
  static const Color purpleDark = Color(0xFF6040E0);
  static const Color blurple = Color(0xFF5865F2);

  // ── Status ──
  static const Color online = Color(0xFF3BA55D);
  static const Color idle = Color(0xFFFAA81A);
  static const Color dnd = Color(0xFFED4245);
  static const Color offline = Color(0xFF747F8D);

  // ── Text ──
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB9BBBE);
  static const Color textMuted = Color(0xFF72767D);
  static const Color textLink = Color(0xFF00AFF4);

  // ── Controls ──
  static const Color hangUp = Color(0xFFED4245);
  static const Color controlBg = Color(0xFF2F2248);
  static const Color controlActive = Color(0xFF43B581);
  static const Color controlInactive = Color(0xFFB9BBBE);

  // ── Dividers ──
  static const Color divider = Color(0xFF2C1660);

  // ── Accent glow for active elements ──
  static const List<BoxShadow> purpleGlow = [
    BoxShadow(color: Color(0x558B6FFF), blurRadius: 12, spreadRadius: 0),
  ];

  // ── Gradient shorthand ──
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [gradientStart, gradientMid, gradientEnd],
    stops: [0.0, 0.5, 1.0],
  );

  // ── Overlay gradient for video areas ──
  static const LinearGradient videoOverlayGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Colors.transparent, Color(0xCC0D0626)],
  );
}
