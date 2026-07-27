import 'dart:async';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/skin_provider.dart';
import '../../config/skins/skin_config.dart';
import '../../core/hrv/hrv_references.dart';

// ── Medición de FC/HRV matutino por PPG ──────────────────────────
// El dedo tapa la cámara trasera con el flash (linterna) encendido; la cámara
// capta los micro-cambios de brillo del dedo con cada latido. De ahí sale la
// FC (fiable) y una ESTIMACIÓN de HRV (rMSSD) para readiness — NO es un dato
// clínico; para máxima precisión, banda de pecho. Devuelve {hrv, hr} al cerrar.
class HrvCameraScreen extends ConsumerStatefulWidget {
  const HrvCameraScreen({super.key});

  @override
  ConsumerState<HrvCameraScreen> createState() => _HrvCameraScreenState();
}

class _HrvCameraScreenState extends ConsumerState<HrvCameraScreen> {
  static const int _durationSec = 45;
  static const int _warmupMs = 4000; // descartar el arranque (dedo + auto-exposición)

  CameraController? _cam;
  bool _initializing = true;
  String? _error;
  bool _measuring = false;
  bool _done = false;
  int _remaining = _durationSec;
  int _bpmLive = 0;

  final List<double> _values = [];
  final List<int> _times = []; // ms desde el inicio de la medición
  Timer? _timer;
  int _t0 = 0;

  int? _resultHr;
  int? _resultHrv;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final cams = await availableCameras();
      final rear = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      final c = CameraController(
        rear,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _cam = c;
        _initializing = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error =
              'No se pudo abrir la cámara. Concede el permiso e inténtalo de nuevo.';
          _initializing = false;
        });
      }
    }
  }

  Future<void> _start() async {
    if (_cam == null || _measuring) return;
    _values.clear();
    _times.clear();
    _t0 = DateTime.now().millisecondsSinceEpoch;
    // El flash se enciende SOLO al medir (no al abrir la pantalla).
    try {
      await _cam!.setFlashMode(FlashMode.torch);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _measuring = true;
      _done = false;
      _remaining = _durationSec;
      _bpmLive = 0;
    });
    await _cam!.startImageStream(_onFrame);
    // Tras ~1,2 s (que el auto-ajuste se adapte al dedo + flash), BLOQUEAR
    // exposición y enfoque: si el AGC sigue "peleando" con el pulso, lo
    // distorsiona y aparecen picos falsos (FC/HRV disparados). Los primeros
    // _warmupMs se descartan igualmente en _process.
    Future.delayed(const Duration(milliseconds: 1200), () async {
      try {
        await _cam?.setExposureMode(ExposureMode.locked);
        await _cam?.setFocusMode(FocusMode.locked);
      } catch (_) {}
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _remaining--);
      if (_remaining <= 0) {
        t.cancel();
        _finish();
      }
    });
  }

  void _onFrame(CameraImage img) {
    // Media de brillo del plano Y (luminancia), submuestreada por velocidad.
    final bytes = img.planes[0].bytes;
    int sum = 0, n = 0;
    for (int i = 0; i < bytes.length; i += 16) {
      sum += bytes[i];
      n++;
    }
    if (n == 0) return;
    _values.add(sum / n);
    _times.add(DateTime.now().millisecondsSinceEpoch - _t0);
    // FC en vivo ~1 vez/segundo
    if (_values.length % 12 == 0) {
      final hr = _process().$1;
      if (hr > 0 && mounted) setState(() => _bpmLive = hr);
    }
  }

  Future<void> _finish() async {
    _timer?.cancel();
    try {
      await _cam?.stopImageStream();
    } catch (_) {}
    try {
      await _cam?.setFlashMode(FlashMode.off);
    } catch (_) {}
    // Volver a auto para que una nueva medición ("Repetir") parta limpia.
    try {
      await _cam?.setExposureMode(ExposureMode.auto);
      await _cam?.setFocusMode(FocusMode.auto);
    } catch (_) {}
    final res = _process();
    if (!mounted) return;
    setState(() {
      _measuring = false;
      _done = true;
      _resultHr = res.$1 > 0 ? res.$1 : null;
      _resultHrv = res.$2 > 0 ? res.$2 : null;
    });
  }

  // ── Procesado PPG: arranque → suavizado → detrend → picos → FC + rMSSD ──
  (int, int) _process() {
    // 0) Descartar el ARRANQUE (dedo asentándose + auto-exposición todavía
    //    adaptándose): los primeros _warmupMs de muestras no se usan.
    final vals = <double>[];
    final ts = <int>[];
    for (int i = 0; i < _values.length; i++) {
      if (_times[i] >= _warmupMs) {
        vals.add(_values[i]);
        ts.add(_times[i]);
      }
    }
    if (vals.length < 40) return (0, 0);
    // 1) PASO BANDA. Suavizado FUERTE (dos pasadas de media móvil de 5 →
    //    lowpass ~2,6 Hz) para eliminar el ruido de alta frecuencia, y detrend
    //    (restar media móvil ancha ~1 s) para quitar la deriva de brillo. El
    //    resultado es una onda de pulso limpia → picos bien ubicados en el
    //    tiempo, que es de lo que depende la precisión del HRV (rMSSD).
    final sm = _movAvg(_movAvg(vals, 2), 2);
    final base = _movAvg(sm, 15);
    final detr = List<double>.filled(sm.length, 0);
    for (int i = 0; i < sm.length; i++) {
      detr[i] = sm[i] - base[i];
    }
    // 3) Picos: MÁXIMO LOCAL en ±3 muestras, por encima de 0,6·desv.típica, con
    //    periodo refractario 350 ms (máx. ~170 ppm) → no cuenta picos falsos.
    final std = _std(detr);
    if (std <= 0) return (0, 0);
    final thr = std * 0.6;
    final peaks = <double>[]; // tiempos de pico en ms (con precisión sub-frame)
    double last = -1000;
    for (int i = 3; i < detr.length - 3; i++) {
      if (detr[i] <= thr) continue;
      bool localMax = true;
      for (int k = i - 3; k <= i + 3; k++) {
        if (detr[k] > detr[i]) {
          localMax = false;
          break;
        }
      }
      if (!localMax || ts[i] - last <= 350) continue;
      // Interpolación parabólica: estima el instante REAL del pico ENTRE
      // fotogramas. A ~30 fps cada muestra dista ~33 ms; sin esto, el jitter de
      // ±1 frame por latido infla el rMSSD (HRV). El vértice de la parábola que
      // pasa por (i-1, i, i+1) recupera la precisión de tiempo perdida.
      final denom = detr[i - 1] - 2 * detr[i] + detr[i + 1];
      double tPeak = ts[i].toDouble();
      if (denom < 0) {
        final frac = 0.5 * (detr[i - 1] - detr[i + 1]) / denom;
        if (frac > -1 && frac < 1) {
          final dtLocal = (ts[i + 1] - ts[i - 1]) / 2.0;
          tPeak = ts[i] + frac * dtLocal;
        }
      }
      peaks.add(tPeak);
      last = tPeak;
    }
    if (peaks.length < 5) return (0, 0);
    // 4) Intervalos latido-a-latido (IBI): rango fisiológico (40–170 ppm) +
    //    rechazo de artefactos por desviación de la MEDIANA (robusto a fallos).
    //    Margen 30%: la cámara es más ruidosa que un sensor de contacto.
    var ibis = <double>[];
    for (int i = 1; i < peaks.length; i++) {
      ibis.add((peaks[i] - peaks[i - 1]).toDouble());
    }
    ibis = ibis.where((x) => x >= 350 && x <= 1500).toList();
    if (ibis.length < 4) return (0, 0);
    final med = _median(ibis);
    if (med <= 0) return (0, 0);
    final clean = ibis.where((x) => (x - med).abs() / med < 0.30).toList();
    if (clean.length < 4) return (0, 0);
    // 5) FC = 60000 / IBI medio · HRV = rMSSD (sobre los IBI limpios).
    final meanIbi = clean.reduce((a, b) => a + b) / clean.length;
    final hr = (60000 / meanIbi).round();
    double sq = 0;
    int m = 0;
    for (int i = 1; i < clean.length; i++) {
      final d = clean[i] - clean[i - 1];
      sq += d * d;
      m++;
    }
    final rmssd = m > 0 ? sqrt(sq / m).round() : 0;
    if (hr < 40 || hr > 170) return (0, 0);
    return (hr, rmssd);
  }

  // Media móvil (ventana ±half): filtro paso bajo reutilizable.
  List<double> _movAvg(List<double> v, int half) {
    final out = List<double>.filled(v.length, 0);
    for (int i = 0; i < v.length; i++) {
      final a = max(0, i - half), b = min(v.length - 1, i + half);
      double s = 0;
      for (int j = a; j <= b; j++) {
        s += v[j];
      }
      out[i] = s / (b - a + 1);
    }
    return out;
  }

  double _median(List<double> v) {
    if (v.isEmpty) return 0;
    final s = [...v]..sort();
    final mid = s.length ~/ 2;
    return s.length.isOdd ? s[mid] : (s[mid - 1] + s[mid]) / 2;
  }

  double _std(List<double> v) {
    if (v.isEmpty) return 0;
    final mean = v.reduce((a, b) => a + b) / v.length;
    double s = 0;
    for (final x in v) {
      s += (x - mean) * (x - mean);
    }
    return sqrt(s / v.length);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _cam?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = ref.watch(activeSkinProvider);
    return Scaffold(
      backgroundColor: skin.background,
      appBar: AppBar(
        backgroundColor: skin.backgroundSecondary,
        foregroundColor: skin.textPrimary,
        title: Text('MEDIR HRV',
            style: TextStyle(
                color: skin.textPrimary, letterSpacing: 2, fontSize: 14)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _error != null
            ? _center(skin, Icons.videocam_off_rounded, _error!)
            : _initializing
                ? Center(child: CircularProgressIndicator(color: skin.accent))
                : _done
                    ? _result(skin)
                    : _live(skin),
      ),
    );
  }

  Widget _live(SkinConfig skin) =>
      _measuring ? _measuringView(skin) : _introView(skin);

  // ── Intro: guía visual en 3 pasos + botón ──────────────────────
  Widget _introView(SkinConfig skin) {
    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 4),
          Text('Medir tu HRV',
              style: TextStyle(
                  color: skin.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          // Pasos 1 y 2 en fila.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _guideCard(
                skin,
                '1',
                'Usa el índice',
                SizedBox(
                  width: 92,
                  height: 100,
                  child: CustomPaint(
                    painter: _HandPainter(
                        fill: const Color(0xFFD9A57E),
                        dot: const Color(0xFFE53935)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _guideCard(
                skin,
                '2',
                'Tápala con la yema',
                SizedBox(width: 92, height: 100, child: _fingerToCameraArt(skin)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Paso 3: cómo queda (móvil con el dedo sobre cámara + flash).
          _guideCard(
            skin,
            '3',
            'Cámara y flash, juntos',
            SizedBox(width: 150, height: 140, child: _placementArt(skin)),
            width: 200,
          ),
          const SizedBox(height: 18),
          Text(
            'Sin apretar. Colócalo ANTES de empezar y no te muevas $_durationSec s.',
            textAlign: TextAlign.center,
            style:
                TextStyle(color: skin.textSecondary, fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _start,
              child: const Text('COMENZAR',
                  style:
                      TextStyle(fontWeight: FontWeight.w700, letterSpacing: 2)),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  // ── Medición en curso ──────────────────────────────────────────
  Widget _measuringView(SkinConfig skin) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.favorite, color: skin.error, size: 110),
        const SizedBox(height: 20),
        Text('$_remaining s',
            style: TextStyle(
                color: skin.textPrimary,
                fontSize: 40,
                fontWeight: FontWeight.w800,
                fontFamily: skin.fontFamilyMono)),
        const SizedBox(height: 8),
        Text(
          _bpmLive > 0 ? '$_bpmLive ppm' : 'Detectando pulso…',
          style: TextStyle(
              color: _bpmLive > 0 ? skin.accent : skin.textMuted,
              fontSize: 18,
              fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 24),
        Text('Mantén el dedo sobre la cámara y el flash.',
            textAlign: TextAlign.center,
            style: TextStyle(color: skin.textMuted, fontSize: 13)),
      ],
    );
  }

  // Tarjeta contenedora de cada paso de la guía visual.
  Widget _guideCard(SkinConfig skin, String n, String caption, Widget art,
      {double width = 128}) {
    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: skin.backgroundSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: skin.textMuted.withOpacity(0.2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration:
                BoxDecoration(color: skin.accent, shape: BoxShape.circle),
            child: Text(n,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 6),
          art,
          const SizedBox(height: 6),
          Text(caption,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: skin.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // Paso 2: la yema subiendo sobre la cámara + flash (flecha de movimiento).
  Widget _fingerToCameraArt(SkinConfig skin) {
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        Positioned(
          top: 2,
          child: Container(
            width: 74,
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: skin.textPrimary.withOpacity(0.13),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 17,
                  height: 17,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: skin.background,
                    border: Border.all(color: skin.textSecondary, width: 3),
                  ),
                ),
                Container(
                  width: 11,
                  height: 11,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFFFFC107),
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          top: 36,
          child: Icon(Icons.keyboard_double_arrow_up,
              size: 20, color: skin.accent),
        ),
        Positioned(
          top: 52,
          child: Icon(Icons.touch_app, size: 46, color: skin.accent),
        ),
      ],
    );
  }

  Widget _result(SkinConfig skin) {
    final ok = _resultHr != null;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(ok ? Icons.check_circle : Icons.error_outline,
            color: ok ? skin.success : skin.warning, size: 72),
        const SizedBox(height: 16),
        if (ok) ...[
          Text('Medición lista',
              style: TextStyle(
                  color: skin.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _stat(skin, '$_resultHr', 'ppm (FC)', skin.error,
                  ref: _resultHr != null ? fcRestLabel(_resultHr!) : null),
              const SizedBox(width: 20),
              _stat(skin, _resultHrv != null ? '$_resultHrv' : '—',
                  'ms (HRV)', skin.accent),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Estimación para tu readiness — no es un dato clínico. Para máxima '
            'precisión, usa una banda de pecho.',
            textAlign: TextAlign.center,
            style: TextStyle(color: skin.textMuted, fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context)
                  .pop({'hr': _resultHr, 'hrv': _resultHrv}),
              child: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('USAR VALORES',
                    maxLines: 1,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => setState(() => _done = false),
            child: Text('Repetir', style: TextStyle(color: skin.textMuted)),
          ),
        ] else ...[
          Text('No se captó bien el pulso',
              style: TextStyle(
                  color: skin.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Text(
            'Cubre por completo la cámara y el flash con el dedo, sin apretar '
            'demasiado, y mantente quieto. Vuelve a intentarlo.',
            textAlign: TextAlign.center,
            style: TextStyle(color: skin.textSecondary, fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () => setState(() => _done = false),
              child: const Text('REINTENTAR',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, letterSpacing: 2)),
            ),
          ),
        ],
      ],
    );
  }

  // Paso 3: móvil con la yema tapando cámara + flash (versión compacta).
  Widget _placementArt(SkinConfig skin) {
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        // Cuerpo del móvil (visto por detrás).
        Positioned(
          top: 0,
          child: Container(
            width: 84,
            height: 132,
            decoration: BoxDecoration(
              color: skin.textPrimary.withOpacity(0.05),
              borderRadius: BorderRadius.circular(18),
              border:
                  Border.all(color: skin.textMuted.withOpacity(0.5), width: 2),
            ),
          ),
        ),
        // Módulo de cámara: lente (anillo) + flash (punto amarillo).
        Positioned(
          top: 14,
          child: Container(
            width: 66,
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: skin.textPrimary.withOpacity(0.13),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: skin.background,
                    border: Border.all(color: skin.textSecondary, width: 3),
                  ),
                ),
                Container(
                  width: 11,
                  height: 11,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFFFFC107),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Zona de la yema (translúcida): cubre a la vez cámara + flash.
        Positioned(
          top: 6,
          child: Container(
            width: 78,
            height: 48,
            decoration: BoxDecoration(
              color: skin.accent.withOpacity(0.16),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: skin.accent, width: 2),
            ),
          ),
        ),
        // Dedo índice tocando la zona.
        Positioned(
          top: 44,
          child: Icon(Icons.touch_app, size: 60, color: skin.accent),
        ),
      ],
    );
  }

  Widget _stat(SkinConfig skin, String value, String label, Color color,
          {String? ref}) =>
      SizedBox(
        width: 135,
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    color: color,
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    fontFamily: skin.fontFamilyMono)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: skin.textMuted, fontSize: 12)),
            if (ref != null) ...[
              const SizedBox(height: 5),
              Text(ref,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: color, fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      );

  Widget _center(SkinConfig skin, IconData icon, String text) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: skin.textMuted, size: 56),
            const SizedBox(height: 16),
            Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(color: skin.textSecondary, fontSize: 15)),
          ],
        ),
      );
}

// ── Mano estilizada (palma abierta hacia el deportista) con el dedo ÍNDICE
//    marcado con un punto rojo: indica QUÉ dedo usar. ─────────────────────
class _HandPainter extends CustomPainter {
  final Color fill;
  final Color dot;
  _HandPainter({required this.fill, required this.dot});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final p = Paint()
      ..color = fill
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // Pulgar (lado izquierdo, inclinado) — se dibuja primero.
    canvas.save();
    canvas.translate(w * 0.29, h * 0.64);
    canvas.rotate(-0.85);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset.zero, width: w * 0.17, height: h * 0.36),
        Radius.circular(w * 0.09),
      ),
      p,
    );
    canvas.restore();

    // Cuatro dedos: índice, corazón, anular, meñique.
    final fw = w * 0.135;
    final cols = [w * 0.34, w * 0.47, w * 0.60, w * 0.72];
    final tops = [h * 0.20, h * 0.10, h * 0.16, h * 0.28];
    for (int i = 0; i < 4; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(cols[i] - fw / 2, tops[i], fw, h * 0.62 - tops[i]),
          Radius.circular(fw / 2),
        ),
        p,
      );
    }

    // Palma encima (tapa las bases de los dedos → silueta limpia).
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.24, h * 0.44, w * 0.54, h * 0.44),
        Radius.circular(w * 0.15),
      ),
      p,
    );

    // Punto rojo sobre el ÍNDICE (primer dedo), cerca de la punta.
    final dotC = Offset(cols[0], tops[0] + h * 0.05);
    canvas.drawCircle(dotC, w * 0.09, Paint()..color = dot);
    canvas.drawCircle(
      dotC,
      w * 0.09,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
