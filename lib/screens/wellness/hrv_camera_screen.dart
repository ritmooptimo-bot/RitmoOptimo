import 'dart:async';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/skin_provider.dart';
import '../../config/skins/skin_config.dart';

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
  static const int _durationSec = 60;

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
    final res = _process();
    if (!mounted) return;
    setState(() {
      _measuring = false;
      _done = true;
      _resultHr = res.$1 > 0 ? res.$1 : null;
      _resultHrv = res.$2 > 0 ? res.$2 : null;
    });
  }

  // ── Procesado PPG: detrend → picos → intervalos → FC + rMSSD ────
  (int, int) _process() {
    if (_values.length < 40) return (0, 0);
    // 1) Detrend: restar media móvil (quita la deriva lenta del brillo).
    const w = 8;
    final detr = List<double>.filled(_values.length, 0);
    for (int i = 0; i < _values.length; i++) {
      final a = max(0, i - w), b = min(_values.length - 1, i + w);
      double s = 0;
      for (int j = a; j <= b; j++) {
        s += _values[j];
      }
      detr[i] = _values[i] - s / (b - a + 1);
    }
    // 2) Picos: máximo local por encima de un umbral (0.5·desv.típica) con
    //    distancia mínima entre latidos (300 ms → máx. 200 ppm).
    final std = _std(detr);
    if (std <= 0) return (0, 0);
    final thr = std * 0.5;
    final peaks = <int>[];
    int last = -1000;
    for (int i = 1; i < detr.length - 1; i++) {
      if (detr[i] > thr && detr[i] >= detr[i - 1] && detr[i] > detr[i + 1]) {
        if (_times[i] - last > 300) {
          peaks.add(_times[i]);
          last = _times[i];
        }
      }
    }
    if (peaks.length < 6) return (0, 0);
    // 3) Intervalos latido-a-latido (IBI) válidos + rechazo de artefactos.
    var ibis = <double>[];
    for (int i = 1; i < peaks.length; i++) {
      ibis.add((peaks[i] - peaks[i - 1]).toDouble());
    }
    ibis = ibis.where((x) => x >= 300 && x <= 1500).toList();
    final clean = <double>[];
    for (int i = 0; i < ibis.length; i++) {
      if (i == 0 || (ibis[i] - ibis[i - 1]).abs() / ibis[i - 1] < 0.2) {
        clean.add(ibis[i]);
      }
    }
    if (clean.length < 4) return (0, 0);
    // 4) FC = 60000 / IBI medio · HRV = rMSSD.
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
    if (hr < 30 || hr > 220) return (0, 0);
    return (hr, rmssd);
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

  Widget _live(SkinConfig skin) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.favorite,
            color: skin.error,
            size: _measuring ? 110 : 90),
        const SizedBox(height: 20),
        if (!_measuring) ...[
          Text('Medir tu HRV',
              style: TextStyle(
                  color: skin.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Text(
            'Tapa la cámara trasera y el flash con la yema del dedo, sin apretar. '
            'Quédate quieto durante $_durationSec segundos.',
            textAlign: TextAlign.center,
            style: TextStyle(color: skin.textSecondary, fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _start,
              child: const Text('COMENZAR',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, letterSpacing: 2)),
            ),
          ),
        ] else ...[
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
              _stat(skin, '$_resultHr', 'ppm (FC)', skin.error),
              const SizedBox(width: 32),
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
            height: 52,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context)
                  .pop({'hr': _resultHr, 'hrv': _resultHrv}),
              child: const Text('USAR ESTOS VALORES',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, letterSpacing: 1.5)),
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

  Widget _stat(SkinConfig skin, String value, String label, Color color) =>
      Column(
        children: [
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  fontFamily: skin.fontFamilyMono)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(color: skin.textMuted, fontSize: 12)),
        ],
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
