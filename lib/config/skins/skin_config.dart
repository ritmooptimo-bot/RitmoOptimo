import 'package:flutter/material.dart';

/// Solo sirve para UNA cosa: saber si la piel tiene gemela de día y de noche,
/// que es lo que mira `toggleDarkLight()`. No es un catálogo de pieles.
///
/// `personalizada` es para las que vienen de fuera: el interruptor día/noche las
/// ignora, que es lo correcto, y así **una piel nueva no obliga a tocar nada
/// más** — ni este enum crece, ni hay que entrar en ninguna pantalla.
enum SkinId { darkLight, f1, personalizada }

class SkinConfig {
  final SkinId id;

  /// Identificador interno, en inglés y ÚNICO ('Dark Mode', 'F1 Cockpit'…).
  /// Es con lo que se compara cuál está puesta: no lo traduzcas.
  final String name;

  /// Lo que lee el deportista en Ajustes. Si se deja vacío se usa `name`, para
  /// que una piel de fuera compile sin tener que rellenarlo.
  final String etiqueta;

  /// La línea de debajo en Ajustes ("Rojo Ferrari · Telemetría…"). Vacía = no se
  /// pinta esa línea.
  final String descripcion;

  // ── Backgrounds ─────────────────────────────────────────────
  final Color background;
  final Color backgroundSecondary;
  final Color backgroundCard;
  final Color backgroundOverlay;

  // ── Accents ──────────────────────────────────────────────────
  final Color accent;
  final Color accentSecondary;
  final Color accentGlow;

  // ── Text ─────────────────────────────────────────────────────
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  // ── Semantic ─────────────────────────────────────────────────
  final Color border;
  final Color success;
  final Color warning;
  final Color error;

  // ── Training Zones (Z1–Z5) ───────────────────────────────────
  final Color zone1Color; // Z1 — Recuperación activa
  final Color zone2Color; // Z2 — Base aeróbica
  final Color zone3Color; // Z3 — Aeróbico moderado
  final Color zone4Color; // Z4 — Umbral láctico
  final Color zone5Color; // Z5 — VO2max

  // ── Shape & Typography ───────────────────────────────────────
  final double cardRadius;
  final String fontFamily;
  final String fontFamilyMono;
  final double fontScaleData;
  final bool useMonoForData;

  const SkinConfig({
    required this.id,
    required this.name,
    this.etiqueta = '',
    this.descripcion = '',
    required this.background,
    required this.backgroundSecondary,
    required this.backgroundCard,
    required this.backgroundOverlay,
    required this.accent,
    required this.accentSecondary,
    required this.accentGlow,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.border,
    required this.success,
    required this.warning,
    required this.error,
    required this.zone1Color,
    required this.zone2Color,
    required this.zone3Color,
    required this.zone4Color,
    required this.zone5Color,
    required this.cardRadius,
    required this.fontFamily,
    required this.fontFamilyMono,
    required this.fontScaleData,
    required this.useMonoForData,
  });

  // Devuelve el color de zona por número (1–5)
  Color zoneColor(int zone) {
    switch (zone) {
      case 1: return zone1Color;
      case 2: return zone2Color;
      case 3: return zone3Color;
      case 4: return zone4Color;
      case 5: return zone5Color;
      default: return textMuted;
    }
  }

  // Genera el ThemeData de Flutter a partir del skin
  ThemeData toTheme() {
    final isDark = background.computeLuminance() < 0.5;
    final colorScheme = isDark
        ? ColorScheme.dark(
            primary: accent,
            secondary: accentSecondary,
            surface: backgroundCard,
            onPrimary: textPrimary,
            onSurface: textPrimary,
            error: error,
          )
        : ColorScheme.light(
            primary: accent,
            secondary: accentSecondary,
            surface: backgroundCard,
            onPrimary: background,
            onSurface: textPrimary,
            error: error,
          );
    return ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      colorScheme: colorScheme,
      cardTheme: CardThemeData(
        color: backgroundCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: BorderSide(color: border, width: 1),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: backgroundSecondary,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
      ),
      textTheme: TextTheme(
        displayLarge: TextStyle(color: textPrimary, fontFamily: fontFamily),
        displayMedium: TextStyle(color: textPrimary, fontFamily: fontFamily),
        bodyLarge: TextStyle(color: textPrimary, fontFamily: fontFamily),
        bodyMedium: TextStyle(color: textSecondary, fontFamily: fontFamily),
        bodySmall: TextStyle(color: textMuted, fontFamily: fontFamily),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(cardRadius),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: backgroundSecondary,
        selectedItemColor: accent,
        unselectedItemColor: textMuted,
        elevation: 0,
      ),
    );
  }
}
