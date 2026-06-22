import 'package:flutter/material.dart';
import 'skin_config.dart';

// ── SKIN 2: F1 Cockpit ───────────────────────────────────────────

const f1Skin = SkinConfig(
  id: SkinId.f1,
  name: 'F1 Cockpit',

  background:          Color(0xFF050507),
  backgroundSecondary: Color(0xFF0D0D10),
  backgroundCard:      Color(0xFF121215),
  backgroundOverlay:   Color(0xCC000000),

  accent:              Color(0xFFE10600),
  accentSecondary:     Color(0xFFFFD700),
  accentGlow:          Color(0x55E10600),

  textPrimary:         Color(0xFFFFFFFF),
  textSecondary:       Color(0xFFB8B8C4),
  textMuted:           Color(0xFF555560),

  border:              Color(0xFFE10600),
  success:             Color(0xFF00FF88),
  warning:             Color(0xFFFFD700),
  error:               Color(0xFFFF3300),

  zone1Color:          Color(0xFF00E676),
  zone2Color:          Color(0xFF69F0AE),
  zone3Color:          Color(0xFFFFD740),
  zone4Color:          Color(0xFFFF6D00),
  zone5Color:          Color(0xFFE10600),

  cardRadius:      4,
  fontFamily:      'Formula1',
  fontFamilyMono:  'RobotoMono',
  fontScaleData:   1.05,
  useMonoForData:  true,
);
