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

// ── Explicaciones COMPLETAS y personalizadas (para el diálogo "ⓘ") ──────────

// FC en reposo, con el valor del deportista y las referencias de forma.
String fcInfoText(int fc) {
  final lbl = fcRestLabel(fc);
  return 'Tu FC en reposo es de $fc ppm${lbl != null ? ' ($lbl)' : ''}.\n\n'
      'Son tus pulsaciones estando en calma. Cuanto más baja, mejor forma '
      'cardiovascular tienes.\n\n'
      'Referencia por forma física:\n'
      '·  menos de 60 ppm — muy en forma\n'
      '·  60-70 — buena\n'
      '·  70-80 — normal\n'
      '·  más de 80 — algo alta\n\n'
      'La media de un adulto activo ronda 60-70 ppm; los deportistas bien '
      'entrenados suelen bajar de 55. Lo mejor para tu salud es una FC en reposo '
      'baja y estable. Si te sube varios días seguidos respecto a tu normal, '
      'puede ser fatiga, estrés o falta de descanso.';
}

// HRV (rMSSD) por edad, con el valor del deportista y qué es lo óptimo.
String hrvInfoText(int? hrv, int? age, {bool cameraEstimate = false}) {
  final v = (hrv != null && hrv > 0) ? '$hrv ms' : 'sin dato fiable';
  final b = StringBuffer();
  b.write('Tu HRV es de $v.\n\n');
  b.write('El HRV (variabilidad de la frecuencia cardíaca) mide cuánto varía el '
      'tiempo entre tus latidos. Más variabilidad = tu sistema nervioso está más '
      'recuperado y menos estresado. Es de los mejores indicadores de recuperación.\n\n');
  if (age != null) {
    final (lo, hi) = hrvTypicalRange(age);
    final mid = ((lo + hi) / 2).round();
    b.write('Para tu edad ($age años):\n'
        '·  típico / media: en torno a $lo-$hi ms (centro ~$mid)\n'
        '·  cuanto MÁS alto, mejor recuperación\n'
        '·  por debajo del rango: más carga o estrés\n\n');
  }
  b.write('LO MÁS IMPORTANTE: el valor de un día varía mucho (por sueño, estrés, '
      'café, alcohol…). No te fijes en el número suelto, sino en tu TENDENCIA '
      'respecto a tu propia media — por eso conviene medirlo a diario, a la misma '
      'hora (recién despierto). Un día bajo no es alarma; una bajada mantenida sí '
      'te dice que priorices descanso.');
  if (cameraEstimate) {
    b.write('\n\nNota: medido con la cámara es una ESTIMACIÓN. Para un HRV preciso, '
        'una banda de pecho (Polar H10, Garmin HRM).');
  }
  return b.toString();
}
