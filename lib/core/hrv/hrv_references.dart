// ── Referencias poblacionales suaves para FC reposo y HRV (rMSSD) ──────────
// Contexto para que el deportista interprete su número, SIN alarmar. La
// referencia PRINCIPAL sigue siendo la individual (su línea base de 7 días);
// esto es solo un apoyo, sobre todo mientras no hay base.

// FC en reposo → rangos de forma física del adulto (independientes de la edad).
String? fcRestLabel(int fc) {
  if (fc <= 0) return null;
  if (fc < 50) return 'excelente · muy entrenado';
  if (fc < 60) return 'muy buena forma';
  if (fc < 70) return 'buena';
  if (fc < 80) return 'normal';
  return 'algo alta';
}

// rMSSD típico por franja de edad (el HRV baja con la edad). Bandas amplias:
// la variación individual es enorme, por eso se presenta como "típico".
(int, int) hrvTypicalRange(int age) {
  if (age < 30) return (40, 75);
  if (age < 40) return (32, 65);
  if (age < 50) return (26, 55);
  if (age < 60) return (22, 48);
  return (18, 42);
}

// HRV (rMSSD) frente a lo típico para la edad. Lenguaje suave (no alarmar).
String? hrvAgeLabel(int rmssd, int? age) {
  if (rmssd <= 0 || age == null) return null;
  final (lo, hi) = hrvTypicalRange(age);
  if (rmssd < lo) return 'en la parte baja para tu edad';
  if (rmssd > hi) return 'alto para tu edad · buen signo';
  return 'normal para tu edad';
}
