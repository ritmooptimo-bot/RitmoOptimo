import 'package:flutter/material.dart';
import 'skin_config.dart';

// ── SKIN 1: Modo Oscuro / Modo Día ──────────────────────────────

const darkSkin = SkinConfig(
  id: SkinId.darkLight,
  name: 'Dark Mode',

  background:          Color(0xFF0A0A0F),
  backgroundSecondary: Color(0xFF111118),
  backgroundCard:      Color(0xFF1A1A24),
  backgroundOverlay:   Color(0x99000000),

  accent:              Color(0xFF00D4FF),
  accentSecondary:     Color(0xFF7B61FF),
  accentGlow:          Color(0x4400D4FF),

  textPrimary:         Color(0xFFFFFFFF),
  textSecondary:       Color(0xFFB0B0C0),
  textMuted:           Color(0xFF606070),

  border:              Color(0xFF2A2A3A),
  success:             Color(0xFF00E676),
  warning:             Color(0xFFFFB300),
  error:               Color(0xFFFF5252),

  zone1Color:          Color(0xFF64B5F6),
  zone2Color:          Color(0xFF81C784),
  zone3Color:          Color(0xFFFFEE58),
  zone4Color:          Color(0xFFFF9800),
  zone5Color:          Color(0xFFF44336),

  cardRadius:      16,
  fontFamily:      'Inter',
  fontFamilyMono:  'RobotoMono',
  fontScaleData:   1.0,
  useMonoForData:  false,
);

const lightSkin = SkinConfig(
  id: SkinId.darkLight,
  name: 'Light Mode',

  background:          Color(0xFFF5F5F8),
  backgroundSecondary: Color(0xFFFFFFFF),
  backgroundCard:      Color(0xFFFFFFFF),
  backgroundOverlay:   Color(0x55FFFFFF),

  accent:              Color(0xFF0077CC),
  accentSecondary:     Color(0xFF5E35B1),
  accentGlow:          Color(0x220077CC),

  textPrimary:         Color(0xFF0D0D14),
  textSecondary:       Color(0xFF44445A),
  textMuted:           Color(0xFF9090A0),

  border:              Color(0xFFE0E0EE),
  success:             Color(0xFF2E7D32),
  warning:             Color(0xFFE65100),
  error:               Color(0xFFC62828),

  zone1Color:          Color(0xFF1E88E5),
  zone2Color:          Color(0xFF43A047),
  zone3Color:          Color(0xFFF9A825),
  zone4Color:          Color(0xFFEF6C00),
  zone5Color:          Color(0xFFC62828),

  cardRadius:      16,
  fontFamily:      'Inter',
  fontFamilyMono:  'RobotoMono',
  fontScaleData:   1.0,
  useMonoForData:  false,
);
