import 'package:flutter/material.dart';

class AppColors {
  // ── FabFoods Brand ────────────────────────────────────────────────────────
  static const primary       = Color(0xFF0F0D0B);   // near-black (logo bg)
  static const primaryLight  = Color(0xFF2A1506);   // dark brown (logo top face)
  static const accent        = Color(0xFFE8820C);   // amber orange (logo left face)
  static const accentSoft    = Color(0xFFF5A535);   // lighter orange
  static const cream         = Color(0xFFEDD9A3);   // cream (logo right face)

  // ── Grey Scale (dark → light) ─────────────────────────────────────────────
  static const grey900       = Color(0xFF1A1A1A);   // deepest — almost black
  static const grey800       = Color(0xFF2C2C2C);   // dark panels
  static const grey700       = Color(0xFF3D3D3D);   // elevated cards
  static const grey600       = Color(0xFF525252);   // borders, dividers
  static const grey500       = Color(0xFF6E6E6E);   // secondary text
  static const grey400       = Color(0xFF8F8F8F);   // hint text
  static const grey300       = Color(0xFFB0B0B0);   // disabled
  static const grey200       = Color(0xFFD4D4D4);   // light borders
  static const grey100       = Color(0xFFEAEAEA);   // surface alt
  static const grey50        = Color(0xFFF4F4F4);   // lightest background

  // ── Semantic mappings ─────────────────────────────────────────────────────
  static const bg            = grey50;              // page background
  static const surface       = Color(0xFFFFFFFF);   // card base (pure white)
  static const surfaceAlt    = grey100;             // input fields, chips
  static const surfaceRaised = grey200;             // borders

  // ── Status ────────────────────────────────────────────────────────────────
  static const success       = Color(0xFF2ECC71);
  static const warning       = Color(0xFFF39C12);
  static const error         = Color(0xFFE74C3C);
  static const info          = Color(0xFF3498DB);

  // ── Payment methods ───────────────────────────────────────────────────────
  static const cash          = Color(0xFF27AE60);
  static const momo          = Color(0xFFE8820C);
  static const visa          = Color(0xFF2980DB);
  static const debt          = Color(0xFF8E44AD);

  // ── Text ──────────────────────────────────────────────────────────────────
  static const textPrimary   = Color(0xFF1A1A1A);   // on light bg
  static const textSecondary = Color(0xFF525252);
  static const textHint      = Color(0xFF8F8F8F);
  static const textOnDark    = Color(0xFFFFFFFF);   // on dark/grey panels
}