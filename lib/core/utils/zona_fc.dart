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
library;

/// Número de zona (1-5), o null si de ahí no sale un número.
int? zonaFcNumero(dynamic valor) {
  if (valor == null) return null;
  if (valor is int) return (valor >= 1 && valor <= 5) ? valor : null;
  final m = RegExp(r'[1-5]').firstMatch(valor.toString());
  return m == null ? null : int.parse(m.group(0)!);
}

/// Etiqueta para la pantalla: "Z2 FC".
///
/// Si no se reconoce un número se devuelve el texto tal cual (sin anteponer
/// otra Z): más vale enseñar lo que puso el entrenador que inventar una zona.
String? etiquetaZonaFc(dynamic valor) {
  if (valor == null) return null;
  final n = zonaFcNumero(valor);
  if (n != null) return 'Z$n FC';
  final txt = valor.toString().trim();
  return txt.isEmpty ? null : txt;
}
