import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/skin_provider.dart';
import '../../config/skins/skin_config.dart';
import '../../core/ble/ble_service.dart';

// ── Medición de HRV/FC con BANDA DE PECHO (BLE) ──────────────────────
// A diferencia de la cámara (estimación PPG), la banda envía los intervalos
// R-R reales (característica 0x2A37, flag bit 4) → HRV (rMSSD) PRECISO, del
// nivel de un pulsómetro. Reutiliza la BleScanScreen para conectar el sensor.
// Devuelve {hr, hrv, method:'band'} al cerrar.
class HrvBandScreen extends ConsumerStatefulWidget {
  const HrvBandScreen({super.key});

  @override
  ConsumerState<HrvBandScreen> createState() => _HrvBandScreenState();
}

enum _Phase { intro, measuring, result }

class _HrvBandScreenState extends ConsumerState<HrvBandScreen> {
  static const int _durationSec = 60;
  static const int _stabilizeSec = 10; // descartar el arranque (asentamiento)

  late final BleService _ble;
  _Phase _phase = _Phase.intro;
  String? _error;

  final List<double> _rr = []; // intervalos R-R en ms
  StreamSubscription<List<double>>? _rrSub;
  StreamSubscription<int>? _hrSub;
  Timer? _timer;
  int _remaining = _durationSec;
  int _elapsed = 0; // segundos transcurridos (para descartar el arranque)
  int _hrLive = 0;

  int? _resultHr;
  int? _resultHrv;
  bool _noRr = false;

  @override
  void initState() {
    super.initState();
    _ble = ref.read(bleServiceProvider);
  }

  Future<void> _connectAndMeasure() async {
    setState(() => _error = null);
    try {
      // Si no hay banda conectada, abre la pantalla de escaneo (reutilizada).
      if (!_ble.isConnected) {
        final device =
            await context.push<BluetoothDevice?>('/ble-scan/hrv');
        if (!mounted) return;
        if (device == null && !_ble.isConnected) {
          return; // el usuario canceló
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'No se pudo conectar la banda. Inténtalo de nuevo.');
      }
      return;
    }
    if (!_ble.isConnected) {
      setState(() => _error = 'No hay ninguna banda conectada.');
      return;
    }
    _startMeasuring();
  }

  void _startMeasuring() {
    _rr.clear();
    _elapsed = 0;
    setState(() {
      _phase = _Phase.measuring;
      _remaining = _durationSec;
      _hrLive = 0;
      _noRr = false;
    });
    // Se descartan los primeros _stabilizeSec (la banda se asienta y el
    // deportista se relaja) → rMSSD más limpio. Es la práctica de las apps
    // de HRV; el rMSSD de ~50 s sigue correlacionando casi 1:1 con 5 min.
    _rrSub = _ble.rrStream.listen((rr) {
      if (_elapsed >= _stabilizeSec) _rr.addAll(rr);
    });
    _hrSub = _ble.hrStream.listen((hr) {
      if (mounted) setState(() => _hrLive = hr);
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        _elapsed++;
        _remaining--;
      });
      if (_remaining <= 0) {
        t.cancel();
        _finish();
      }
    });
  }

  void _finish() {
    _rrSub?.cancel();
    _hrSub?.cancel();
    final res = _compute();
    if (!mounted) return;
    setState(() {
      _phase = _Phase.result;
      _resultHr = res.$1 > 0 ? res.$1 : (_hrLive > 0 ? _hrLive : null);
      _resultHrv = res.$2 > 0 ? res.$2 : null;
      _noRr = _rr.isEmpty;
    });
  }

  // rMSSD a partir de los R-R reales de la banda (precisos).
  (int, int) _compute() {
    var rr = _rr.where((x) => x >= 300 && x <= 2000).toList();
    if (rr.length < 8) return (0, 0);
    final med = _median(rr);
    if (med <= 0) return (0, 0);
    rr = rr.where((x) => (x - med).abs() / med < 0.30).toList();
    if (rr.length < 8) return (0, 0);
    final meanRr = rr.reduce((a, b) => a + b) / rr.length;
    final hr = (60000 / meanRr).round();
    double sq = 0;
    int m = 0;
    for (int i = 1; i < rr.length; i++) {
      final d = rr[i] - rr[i - 1];
      sq += d * d;
      m++;
    }
    final rmssd = m > 0 ? sqrt(sq / m).round() : 0;
    if (hr < 30 || hr > 220) return (0, 0);
    return (hr, rmssd);
  }

  double _median(List<double> v) {
    if (v.isEmpty) return 0;
    final s = [...v]..sort();
    final mid = s.length ~/ 2;
    return s.length.isOdd ? s[mid] : (s[mid - 1] + s[mid]) / 2;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _rrSub?.cancel();
    _hrSub?.cancel();
    // Suelta la banda al salir (medición puntual, no de sesión).
    _ble.disconnect();
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
        title: Text('MEDIR HRV · BANDA',
            style: TextStyle(
                color: skin.textPrimary, letterSpacing: 2, fontSize: 14)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: switch (_phase) {
          _Phase.intro => _introView(skin),
          _Phase.measuring => _measuringView(skin),
          _Phase.result => _resultView(skin),
        },
      ),
    );
  }

  Widget _introView(SkinConfig skin) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.monitor_heart_outlined, color: skin.accent, size: 88),
        const SizedBox(height: 20),
        Text('Medir con banda de pecho',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: skin.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Text(
          'La medición más precisa: tu banda envía los intervalos entre latidos '
          'reales. Colócate la banda (humedece el electrodo), siéntate cómodo y '
          'quédate quieto y relajado durante $_durationSec segundos.',
          textAlign: TextAlign.center,
          style: TextStyle(color: skin.textSecondary, fontSize: 14, height: 1.4),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(_error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: skin.error, fontSize: 13)),
        ],
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _connectAndMeasure,
            icon: const Icon(Icons.bluetooth_searching, size: 20),
            label: Text(_ble.isConnected ? 'MEDIR' : 'CONECTAR BANDA Y MEDIR',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, letterSpacing: 1.5)),
          ),
        ),
      ],
    );
  }

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
          _hrLive > 0 ? '$_hrLive ppm' : 'Recibiendo latidos…',
          style: TextStyle(
              color: _hrLive > 0 ? skin.accent : skin.textMuted,
              fontSize: 18,
              fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(
            _elapsed < _stabilizeSec
                ? 'Estabilizando… relájate'
                : '${_rr.length} intervalos R-R captados',
            style: TextStyle(color: skin.textMuted, fontSize: 13)),
        const SizedBox(height: 24),
        Text('Relájate y respira con normalidad. No hables ni te muevas.',
            textAlign: TextAlign.center,
            style: TextStyle(color: skin.textMuted, fontSize: 13)),
      ],
    );
  }

  Widget _resultView(SkinConfig skin) {
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
            _resultHrv != null
                ? 'Medido con banda de pecho: HRV preciso (rMSSD) a partir de los '
                    'intervalos reales entre latidos.'
                : 'Tu banda no envía intervalos R-R, así que no se pudo calcular el '
                    'HRV. La FC sí es válida.',
            textAlign: TextAlign.center,
            style: TextStyle(color: skin.textMuted, fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(
                  {'hr': _resultHr, 'hrv': _resultHrv, 'method': 'ble'}),
              child: const Text('USAR ESTOS VALORES',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, letterSpacing: 1.5)),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => setState(() => _phase = _Phase.intro),
            child: Text('Repetir', style: TextStyle(color: skin.textMuted)),
          ),
        ] else ...[
          Text('No se captaron latidos',
              style: TextStyle(
                  color: skin.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Text(
            _noRr
                ? 'La banda no envió datos. Comprueba que esté bien colocada '
                    'y humedecida, y vuelve a intentarlo.'
                : 'Señal insuficiente. Colócate bien la banda, relájate y repite.',
            textAlign: TextAlign.center,
            style: TextStyle(color: skin.textSecondary, fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () => setState(() => _phase = _Phase.intro),
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
          Text(label, style: TextStyle(color: skin.textMuted, fontSize: 12)),
        ],
      );
}
