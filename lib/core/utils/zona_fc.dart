/// LA ZONA DE FRECUENCIA CARDIACA LLEGA DE MIL FORMAS.
///
/// Según quién creara la sesión, el bloque trae `zone` como `2`, `"2"`, `"z2"`,
/// `"Z2"` o incluso `"z2-z3"`. Tratarla en crudo daba dos fallos distintos:
///
///   · La pantalla de sesión pintaba `'Z$zona FC'` → con `"z1"` salía
///     **"Zz1 FC"**, con la zeta duplicada.
///   · El guion de audio hacía `int.tryParse("z1")` → **null**, así que la voz
///     se callaba la zona del bloque sin que nadie se enterara.
///
/// Mismo origen, así que un solo sitio donde arreglarlo.
///
/// ═══════════════════════════════════════════════════════════════════════
///  ⚠️ Y EL FALLO GRAVE QUE APARECIÓ DESPUÉS (19/08)
/// ═══════════════════════════════════════════════════════════════════════
///
/// La expresión regular `[1-5]` sacaba el dígito de CUALQUIER etiqueta. Con la
/// escala del entrenador —R0, R1, R1+, R2, R3, R3+— pasaba esto:
///
///     "R2"  →  zonaFcNumero → 2  →  etiquetaZonaFc → "Z2 FC"
///
/// El plan decía **R2** (entre VT1 y VT2: 155-164 ppm en David) y la app pintaba
/// **Z2 FC** (116-134 ppm). Treinta pulsaciones menos. El deportista habría
/// hecho su sesión de umbral a ritmo de rodaje suave creyendo que iba bien, y el
/// entrenador habría visto un plan que no era el que se ejecutó.
///
/// **Las dos escalas NO son intercambiables**: la R de Raúl está anclada en
/// umbrales ventilatorios y es percepción; Z1-Z5 es porcentaje de FC máxima.
/// Compartir el dígito no las hace equivalentes.
///
/// La regla de la casa ya existía —`zone_escala`, migración 090: mirar la escala
/// antes de pintar nada— y aquí no se estaba aplicando.
library;

/// ¿Esta etiqueta es de la escala Z (porcentaje de FC máxima)?
///
/// Solo `z1`..`z7` y los dígitos sueltos, que en esta base son z1-z5 heredados
/// del generador antiguo. Todo lo demás —R0, R1+, R3+…— NO lo es.
bool esEscalaFc(dynamic valor) {
  if (valor == null) return false;
  if (valor is num) return valor >= 1 && valor <= 7;
  final t = valor.toString().trim().toLowerCase();
  return RegExp(r'^z?[1-7]$').hasMatch(t);
}

/// Número de zona (1-7) SOLO si la etiqueta es de la escala de FC.
///
/// ⚠️ Devuelve null para `R2` a propósito: de una etiqueta de percepción no sale
/// un número de zona de pulsaciones. Antes devolvía 2 y eso es lo que producía
/// el "Z2 FC" sobre un bloque en R2.
int? zonaFcNumero(dynamic valor) {
  if (!esEscalaFc(valor)) return null;
  if (valor is num) return valor.round();
  final m = RegExp(r'[1-7]').firstMatch(valor.toString());
  return m == null ? null : int.parse(m.group(0)!);
}

/// Etiqueta para la pantalla.
///
/// `escala` es lo que dice el propio bloque (`zone_escala`): si viene, MANDA.
/// Sin ella se deduce de la forma de la etiqueta.
///
/// · escala de FC  → "Z2 FC"
/// · percepción    → "R2", tal cual la escribió el entrenador
/// · lo que no se reconozca → tal cual, nunca convertido
String? etiquetaZonaFc(dynamic valor, {String? escala}) {
  if (valor == null) return null;
  final txt = valor.toString().trim();
  if (txt.isEmpty) return null;

  // La escala declarada manda sobre cualquier deducción por la forma.
  if (escala == 'percepcion') return txt.toUpperCase();

  if (escala == 'fc' || esEscalaFc(valor)) {
    final n = zonaFcNumero(valor) ?? int.tryParse(txt.replaceAll(RegExp(r'\D'), ''));
    if (n != null) return 'Z$n FC';
  }

  // Más vale enseñar lo que puso el entrenador que inventar una zona.
  return txt.toUpperCase();
}
