import 'dart:math';

// ── Análisis HRV con corrección de artefactos (estilo Lipponen-Tarvainen) ──
// Módulo compartido por la medición con banda (R-R BLE) y con cámara (PPG).
// Basado en el método que usa Kubios: clasifica cada latido contra la mediana
// local (normal / EXTRA / PERDIDO / ectópico), reconstruye la serie NN limpia,
// refina el ruido residual y calcula rMSSD + lnRMSSD.
//
// Confianza por NIVELES (no binario): con banda ruidosa igual damos una
// ESTIMACIÓN útil para la tendencia del propio deportista, etiquetada como tal;
// solo se oculta si la señal es insuficiente. La FC siempre es la que reporta la
// banda (robusta), no la derivada de R-R contaminados.
// Ref: Lipponen & Tarvainen 2019 (J Med Eng Technol); validez ~80% de latidos
// (Oura/MDPI); lnRMSSD para tendencia (HRV4Training/Elite HRV).

enum HrvConfidence { high, medium, low, none }

class HrvResult {
  final int hr; // FC (ppm) — la que reporta la banda; >0 si válida
  final int rmssd; // rMSSD (ms) de la serie corregida (0 si none)
  final double lnRmssd; // ln(rMSSD)
  final int nClean; // nº de latidos NN finales usados
  final double grossArtifactPct; // basura bruta / total (calidad de la banda)
  final double residualNoisePct; // ruido residual tras corregir
  final HrvConfidence confidence;

  const HrvResult({
    required this.hr,
    required this.rmssd,
    required this.lnRmssd,
    required this.nClean,
    required this.grossArtifactPct,
    required this.residualNoisePct,
    required this.confidence,
  });

  bool get hasHrv => confidence != HrvConfidence.none && rmssd > 0;

  static HrvResult invalid() => const HrvResult(
        hr: 0,
        rmssd: 0,
        lnRmssd: 0,
        nClean: 0,
        grossArtifactPct: 1,
        residualNoisePct: 1,
        confidence: HrvConfidence.none,
      );

  static HrvResult fcOnly(int hr, double grossPct) => HrvResult(
        hr: hr,
        rmssd: 0,
        lnRmssd: 0,
        nClean: 0,
        grossArtifactPct: grossPct,
        residualNoisePct: 1,
        confidence: HrvConfidence.none,
      );
}

/// Analiza una serie de intervalos R-R (ms). `reportedHr` (la FC que reporta la
/// banda) ancla la referencia cuando está disponible (>0), lo que hace la
/// corrección robusta incluso con bandas muy ruidosas.
HrvResult analyzeRr(List<double> rrRaw, {double reportedHr = 0}) {
  final rr = rrRaw.where((x) => x >= 250 && x <= 2200).toList();
  if (rr.length < 12) return HrvResult.invalid();

  // Referencia robusta: la FC de la banda (fiable) o la mediana de la serie.
  final medRR = reportedHr > 0 ? 60000.0 / reportedHr : _median(rr);
  if (medRR <= 0) return HrvResult.invalid();
  final refHr = (60000.0 / medRR).round(); // FC mostrada = la de la banda

  // 1) Clasificación de latidos anclada en medRR (Lipponen-Tarvainen):
  //    EXTRA (espurio corto: x corto y x+siguiente ≈ medRR) → se descarta.
  //    PERDIDO (≈ doble intervalo) → se parte en dos.
  //    NORMAL (dentro de ±25% de medRR) → se conserva. Resto → ectópico/ruido.
  final nn = <double>[];
  int gross = 0;
  for (int i = 0; i < rr.length; i++) {
    final x = rr[i];
    if (i + 1 < rr.length &&
        x < 0.75 * medRR &&
        (x + rr[i + 1] - medRR).abs() < 0.25 * medRR) {
      gross++;
      continue; // EXTRA
    }
    if (x > 1.6 * medRR && (x / 2 - medRR).abs() < 0.25 * medRR) {
      nn.add(x / 2);
      nn.add(x / 2);
      gross++;
      continue; // PERDIDO
    }
    if ((x - medRR).abs() <= 0.25 * medRR) {
      nn.add(x);
    } else {
      gross++; // ectópico / ruido → hueco
    }
  }
  final grossPct = gross / rr.length;
  if (nn.length < 12) return HrvResult.fcOnly(refHr, grossPct);

  // 2) Refinado sucesivo: descarta saltos residuales >15% del ritmo local
  //    (mediana de los últimos 5) y mide cuánto ruido queda tras corregir.
  final nn2 = <double>[];
  int residual = 0;
  for (final x in nn) {
    if (nn2.isEmpty) {
      nn2.add(x);
      continue;
    }
    final recent = nn2.length <= 5 ? nn2 : nn2.sublist(nn2.length - 5);
    final ref = _median([...recent]);
    if (ref > 0 && (x - ref).abs() < 0.15 * ref) {
      nn2.add(x);
    } else {
      residual++;
    }
  }
  final residualPct = nn.isEmpty ? 1.0 : residual / nn.length;
  if (nn2.length < 15) return HrvResult.fcOnly(refHr, grossPct);

  // 3) rMSSD + lnRMSSD sobre la serie NN limpia.
  double sq = 0;
  int m = 0;
  for (int i = 1; i < nn2.length; i++) {
    final d = nn2[i] - nn2[i - 1];
    sq += d * d;
    m++;
  }
  final rmssd = m > 0 ? sqrt(sq / m) : 0.0;

  // 4) CONFIANZA por niveles (basura bruta + ruido residual + nº de latidos).
  //    Con banda ruidosa damos estimación de BAJA confianza (útil para tendencia),
  //    no la ocultamos; solo 'none' si es implausible o hay muy pocos latidos.
  final plausible = rmssd >= 3 && rmssd <= 200 && refHr >= 30 && refHr <= 220;
  HrvConfidence conf;
  if (!plausible) {
    conf = HrvConfidence.none;
  } else if (grossPct < 0.10 && residualPct < 0.12 && nn2.length >= 25) {
    conf = HrvConfidence.high;
  } else if (grossPct < 0.40 && residualPct < 0.22 && nn2.length >= 18) {
    conf = HrvConfidence.medium;
  } else {
    conf = HrvConfidence.low;
  }

  return HrvResult(
    hr: refHr,
    rmssd: rmssd.round(),
    lnRmssd: rmssd > 1 ? log(rmssd) : 0,
    nClean: nn2.length,
    grossArtifactPct: grossPct,
    residualNoisePct: residualPct,
    confidence: conf,
  );
}

double _median(List<double> v) {
  if (v.isEmpty) return 0;
  final s = [...v]..sort();
  final mid = s.length ~/ 2;
  return s.length.isOdd ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}
