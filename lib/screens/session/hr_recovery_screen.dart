import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../config/skins/skin_config.dart';
import '../../providers/skin_provider.dart';
import '../../core/ble/ble_service.dart';
import '../../core/network/api_client.dart';

const _kDurationSec = 120; // 2 minutos

class HrRecoveryScreen extends ConsumerStatefulWidget {
  final String sessionId;
  const HrRecoveryScreen({super.key, required this.sessionId});

  @override
  ConsumerState<HrRecoveryScreen> createState() => _HrRecoveryScreenState();
}

class _HrRecoveryScreenState extends ConsumerState<HrRecoveryScreen> {
  Timer? _timer;
  StreamSubscription<int>? _hrSub;

  int    _elapsed         = 0;
  bool   _running         = false;
  bool   _done            = false;
  bool   _saving          = false;
  int?   _hrStart;        // FC al inicio (media de primeros 5 s)
  int    _currentHR       = 0;
  final List<FlSpot> _hrPoints = [];
  final List<int> _firstSamples = [];

  @override
  void initState() {
    super.initState();
    _subscribeHR();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  void _subscribeHR() {
    final ble = ref.read(bleServiceProvider);
    _hrSub = ble.hrStream.listen((bpm) {
      if (!mounted) return;
      setState(() => _currentHR = bpm);
      if (_running && !_done) {
        _hrPoints.add(FlSpot(_elapsed.toDouble(), bpm.toDouble()));
        if (_hrStart == null && _firstSamples.length < 5) {
          _firstSamples.add(bpm);
          if (_firstSamples.length == 5) {
            _hrStart = (_firstSamples.reduce((a, b) => a + b) / 5).round();
          }
        }
      }
    });
  }

  void _start() {
    if (_running) return;
    setState(() => _running = true);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _elapsed++;
        if (_elapsed >= _kDurationSec) _finish();
      });
    });
  }

  void _finish() {
    _timer?.cancel();
    setState(() {
      _running = false;
      _done    = true;
    });
  }

  Future<void> _save() async {
    if (_hrPoints.length < 5) return;
    setState(() => _saving = true);
    try {
      final hrEnd = _currentHR > 0 ? _currentHR : _hrPoints.last.y.round();
      final hrPeak = _hrStart;
      final payload = {
        'session_id':       widget.sessionId,
        'hr_peak_bpm':      hrPeak,
        'hr_end_bpm':       hrEnd,
        'duration_sec':     _elapsed,
        'hr_series':        _hrPoints.map((p) => {'t': p.x.round(), 'hr': p.y.round()}).toList(),
        'recovery_index':   hrPeak != null && hrPeak > 0 && hrEnd > 0
            ? ((hrPeak - hrEnd) / hrPeak * 100).round()
            : null,
      };
      await ref.read(apiClientProvider).postHRRecovery(payload);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _hrSub?.cancel();
    super.dispose();
  }

  String get _timeLeft {
    final rem = _kDurationSec - _elapsed;
    final m = rem ~/ 60;
    final s = (rem % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final skin = ref.watch(activeSkinProvider);

    return Scaffold(
      backgroundColor: skin.background,
      appBar: AppBar(
        backgroundColor: skin.backgroundSecondary,
        leading: _done
            ? null
            : IconButton(
                icon: Icon(Icons.close, color: skin.textMuted),
                onPressed: () => Navigator.of(context).pop(false),
              ),
        automaticallyImplyLeading: false,
        title: Text(
          'RECUPERACIÓN CARDÍACA',
          style: TextStyle(
              color: skin.textPrimary, fontSize: 13, letterSpacing: 2),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── Instrucción ─────────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: skin.backgroundCard,
                borderRadius: BorderRadius.circular(skin.cardRadius),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: skin.accent, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Detente, respira con calma y mantén el sensor puesto durante 2 minutos.',
                      style: TextStyle(color: skin.textSecondary, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Contador ────────────────────────────────────
            if (!_done) ...[
              Text(
                _timeLeft,
                style: TextStyle(
                  fontFamily: skin.fontFamilyMono,
                  fontSize: 64,
                  fontWeight: FontWeight.w700,
                  color: _elapsed < 60 ? skin.error : skin.success,
                  letterSpacing: 4,
                ),
              ),
              Text(
                'tiempo restante',
                style: TextStyle(color: skin.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: _elapsed / _kDurationSec,
                backgroundColor: skin.border,
                valueColor: AlwaysStoppedAnimation(
                    _elapsed < 60 ? skin.error : skin.success),
                minHeight: 4,
              ),
            ] else ...[
              Icon(Icons.check_circle, color: skin.success, size: 56),
              const SizedBox(height: 8),
              Text(
                'Medición completada',
                style: TextStyle(
                    color: skin.success,
                    fontSize: 18,
                    fontWeight: FontWeight.w700),
              ),
            ],

            const SizedBox(height: 24),

            // ── FC actual ───────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.favorite, color: skin.error, size: 20),
                const SizedBox(width: 8),
                Text(
                  _currentHR > 0 ? '$_currentHR bpm' : '-- bpm',
                  style: TextStyle(
                    fontFamily: skin.fontFamilyMono,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: _currentHR > 0 ? skin.error : skin.textMuted,
                  ),
                ),
                if (_hrStart != null) ...[
                  const SizedBox(width: 16),
                  _Delta(current: _currentHR, start: _hrStart!, skin: skin),
                ],
              ],
            ),

            const SizedBox(height: 24),

            // ── Gráfico FC ──────────────────────────────────
            if (_hrPoints.length >= 2) ...[
              Text(
                'FRECUENCIA CARDÍACA',
                style: TextStyle(
                    color: skin.textMuted, fontSize: 9, letterSpacing: 2),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 140,
                child: _HrChart(points: _hrPoints, skin: skin),
              ),
            ] else
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: skin.accent, strokeWidth: 2),
                      const SizedBox(height: 12),
                      Text(
                        'Esperando datos del sensor…',
                        style: TextStyle(color: skin.textMuted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),

            const Spacer(),

            // ── Botones ────────────────────────────────────
            if (_done)
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? CircularProgressIndicator(
                          color: skin.background, strokeWidth: 2)
                      : const Text(
                          'GUARDAR RECUPERACIÓN',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, letterSpacing: 1.5),
                        ),
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: skin.textMuted,
                    side: BorderSide(color: skin.border),
                  ),
                  child: const Text('Cancelar medición'),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Delta (caída de FC) ──────────────────────────────────────────

class _Delta extends StatelessWidget {
  final int current;
  final int start;
  final SkinConfig skin;
  const _Delta(
      {required this.current, required this.start, required this.skin});

  @override
  Widget build(BuildContext context) {
    final drop = start - current;
    final isGood = drop > 0;
    final color = isGood ? skin.success : skin.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isGood ? Icons.arrow_downward : Icons.arrow_upward,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            '${drop.abs()} bpm',
            style: TextStyle(
                color: color,
                fontFamily: skin.fontFamilyMono,
                fontSize: 13,
                fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

// ── Gráfico de línea FC ──────────────────────────────────────────

class _HrChart extends StatelessWidget {
  final List<FlSpot> points;
  final SkinConfig skin;
  const _HrChart({required this.points, required this.skin});

  @override
  Widget build(BuildContext context) {
    final minY = points.map((p) => p.y).reduce(math.min) - 5;
    final maxY = points.map((p) => p.y).reduce(math.max) + 5;

    return LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
            color: skin.border,
            strokeWidth: 0.5,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (v, _) => Text(
                '${v.round()}',
                style: TextStyle(color: skin.textMuted, fontSize: 9),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 18,
              getTitlesWidget: (v, _) {
                final s = v.round();
                if (s % 30 != 0) return const SizedBox.shrink();
                return Text(
                  '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}',
                  style: TextStyle(color: skin.textMuted, fontSize: 9),
                );
              },
            ),
          ),
          topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: points,
            isCurved: true,
            color: skin.error,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: skin.error.withValues(alpha: 0.08),
            ),
          ),
        ],
      ),
    );
  }
}
