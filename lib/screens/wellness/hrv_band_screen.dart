import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/skin_provider.dart';
import '../../config/skins/skin_config.dart';
import '../../core/ble/ble_service.dart';
import '../../core/hrv/hrv_analysis.dart';
import '../../core/hrv/hrv_references.dart';
import '../../core/hrv/hrv_info_sheet.dart';
import '../../core/network/api_client.dart';

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
  static const int _stabilizeSec = 10; // descartar el arranque (asentamiento)
  static const int _minSec = 30; // mínimo de medición
  static const int _maxSec = 90; // máximo (se alarga si la banda es ruidosa)
  static const int _targetBeats = 45; // latidos limpios objetivo

  late final BleService _ble;
  _Phase _phase = _Phase.intro;
  String? _error;

  final List<double> _rr = []; // intervalos R-R en ms
  StreamSubscription<List<double>>? _rrSub;
  StreamSubscription<int>? _hrSub;
  Timer? _timer;
  int _elapsed = 0; // segundos transcurridos
  int _hrLive = 0;
  int _cleanBeats = 0; // latidos limpios acumulados (progreso en vivo)
  final List<int> _hrSamples = []; // FC que reporta la banda (referencia fiable)

  HrvResult? _result; // análisis final (Lipponen-Tarvainen)
  bool _noSignal = false; // no llegó ningún R-R
  int? _age; // edad del perfil (para la referencia de HRV por edad)

  @override
  void initState() {
    super.initState();
    _ble = ref.read(bleServiceProvider);
    _loadAge();
  }

  Future<void> _loadAge() async {
    try {
      final b = await ref.read(apiClientProvider).getProfileBasics();
      if (mounted) setState(() => _age = b['age'] as int?);
    } catch (_) {}
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
    _hrSamples.clear();
    _elapsed = 0;
    _cleanBeats = 0;
    setState(() {
      _phase = _Phase.measuring;
      _hrLive = 0;
      _noSignal = false;
      _result = null;
    });
    // Se descartan los primeros _stabilizeSec (la banda se asienta y el
    // deportista se relaja). Duración ADAPTATIVA: se mide hasta reunir
    // _targetBeats latidos limpios; con una banda ruidosa se alarga hasta
    // _maxSec, y si aun así no llega, el análisis lo marca como no fiable.
    _rrSub = _ble.rrStream.listen((rr) {
      if (_elapsed >= _stabilizeSec) _rr.addAll(rr);
    });
    _hrSub = _ble.hrStream.listen((hr) {
      if (_elapsed >= _stabilizeSec && hr > 0) _hrSamples.add(hr);
      if (mounted) setState(() => _hrLive = hr);
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      _elapsed++;
      if (_elapsed >= _stabilizeSec) {
        // Cuenta de latidos limpios en vivo (barra de progreso).
        _cleanBeats = analyzeRr(_rr, reportedHr: _reportedHr()).nClean;
        if (_elapsed >= _minSec &&
            (_cleanBeats >= _targetBeats || _elapsed >= _maxSec)) {
          t.cancel();
          _finish();
          return;
        }
      }
      setState(() {});
    });
  }

  double _reportedHr() => _hrSamples.isEmpty
      ? 0
      : _median(_hrSamples.map((e) => e.toDouble()).toList());

  void _finish() {
    _rrSub?.cancel();
    _hrSub?.cancel();
    final r = analyzeRr(_rr, reportedHr: _reportedHr());
    if (!mounted) return;
    setState(() {
      _phase = _Phase.result;
      _result = r;
      _noSignal = _rr.isEmpty;
    });
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
          'quédate quieto y relajado ~1 minuto (se ajusta según la señal).',
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
    final progress = (_cleanBeats / _targetBeats).clamp(0.0, 1.0);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.favorite, color: skin.error, size: 110),
        const SizedBox(height: 20),
        Text(_hrLive > 0 ? '$_hrLive ppm' : 'Recibiendo latidos…',
            style: TextStyle(
                color: _hrLive > 0 ? skin.accent : skin.textMuted,
                fontSize: 34,
                fontWeight: FontWeight.w800,
                fontFamily: skin.fontFamilyMono)),
        const SizedBox(height: 14),
        Text(
            _elapsed < _stabilizeSec
                ? 'Estabilizando… relájate'
                : 'Latidos limpios: $_cleanBeats / $_targetBeats',
            style: TextStyle(
                color: skin.textMuted,
                fontSize: 14,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        SizedBox(
          width: 220,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _elapsed < _stabilizeSec ? null : progress,
              backgroundColor: skin.textMuted.withValues(alpha: 0.2),
              color: skin.accent,
              minHeight: 6,
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('Relájate y respira con normalidad. No hables ni te muevas.',
            textAlign: TextAlign.center,
            style: TextStyle(color: skin.textMuted, fontSize: 13)),
      ],
    );
  }

  Widget _resultView(SkinConfig skin) {
    final r = _result;
    final hasHr = r != null && r.hr > 0;
    if (!hasHr) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, color: skin.warning, size: 72),
          const SizedBox(height: 16),
          Text('No se captaron latidos',
              style: TextStyle(
                  color: skin.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Text(
            _noSignal
                ? 'La banda no envió datos. Comprueba que esté bien colocada '
                    'y humedecida, y vuelve a intentarlo.'
                : 'Señal insuficiente. Colócate bien la banda, relájate y repite.',
            textAlign: TextAlign.center,
            style:
                TextStyle(color: skin.textSecondary, fontSize: 14, height: 1.4),
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
      );
    }
    final showHrv = r.hasHrv;
    final msg = switch (r.confidence) {
      HrvConfidence.high =>
        'HRV preciso (rMSSD) a partir de los intervalos reales entre latidos.',
      HrvConfidence.medium =>
        'Tu banda mete algo de ruido; lo hemos corregido y el HRV es utilizable.',
      HrvConfidence.low =>
        '“Señal ruidosa” = tu banda manda algunos latidos con error. Los corregimos, '
            'así que este HRV es una ESTIMACIÓN (no exacto). Te vale para ver TU '
            'tendencia día a día con esta misma banda. Para un valor preciso: Polar H10 '
            'o Garmin HRM.',
      HrvConfidence.none =>
        'La señal de esta banda no da para calcular el HRV; solo mostramos la FC (esa '
            'sí vale). Para el HRV, una banda de latido limpio (Polar H10, Garmin HRM).',
    };
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(showHrv ? Icons.check_circle : Icons.info_outline,
            color: showHrv ? skin.success : skin.warning, size: 64),
        const SizedBox(height: 14),
        Text('Medición lista',
            style: TextStyle(
                color: skin.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _stat(skin, '${r.hr}', 'ppm (FC)', skin.error,
                ref: fcRestLabel(r.hr)),
            const SizedBox(width: 20),
            _stat(skin, showHrv ? '${r.rmssd}' : '—', 'ms (HRV)', skin.accent,
                ref: showHrv ? hrvAgeLabel(r.rmssd, _age) : null),
          ],
        ),
        const SizedBox(height: 14),
        _qualityBadge(skin, r),
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed: () => showHrvInfoSheet(context, skin,
              fc: r.hr, hrv: showHrv ? r.rmssd : null, age: _age),
          icon: Icon(Icons.info_outline, size: 16, color: skin.accent),
          label: Text('¿Qué significan estos números?',
              style: TextStyle(color: skin.accent, fontSize: 12.5)),
        ),
        const SizedBox(height: 6),
        Text(msg,
            textAlign: TextAlign.center,
            style: TextStyle(color: skin.textMuted, fontSize: 12, height: 1.35)),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pop({
              'hr': r.hr,
              'hrv': showHrv ? r.rmssd : null,
              'method': 'ble',
            }),
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
          onPressed: () => setState(() => _phase = _Phase.intro),
          child: Text('Repetir', style: TextStyle(color: skin.textMuted)),
        ),
      ],
    );
  }

  // Veredicto de la banda según la confianza del análisis.
  Widget _qualityBadge(SkinConfig skin, HrvResult r) {
    final Color color;
    final String label;
    final IconData icon;
    switch (r.confidence) {
      case HrvConfidence.high:
        color = skin.success;
        label = 'Señal limpia';
        icon = Icons.check_circle;
        break;
      case HrvConfidence.medium:
        color = skin.warning;
        label = 'Ruido corregido';
        icon = Icons.warning_amber_rounded;
        break;
      case HrvConfidence.low:
        color = skin.error;
        label = 'Estimación';
        icon = Icons.info_outline;
        break;
      case HrvConfidence.none:
        color = skin.error;
        label = 'Sin HRV fiable';
        icon = Icons.error_outline;
        break;
    }
    final cleanPct = (100 - r.grossArtifactPct * 100).round().clamp(0, 100);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Text('$label · $cleanPct% limpio',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
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
}
