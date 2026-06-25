import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/skin_provider.dart';
import '../../providers/workout_provider.dart';
import '../../config/router.dart';

// ── Session Complete Screen ──────────────────────────────────────
// Atleta registra los datos reales al finalizar la sesión.
// Los campos de duración, distancia y FC se pre-rellenan desde
// los sensores BLE/GPS si estuvieron activos durante la sesión.
// Llama a POST /sessions/:id/complete → dispara evaluateSessionAlerts().

class SessionCompleteScreen extends ConsumerStatefulWidget {
  final String sessionId;
  const SessionCompleteScreen({super.key, required this.sessionId});

  @override
  ConsumerState<SessionCompleteScreen> createState() =>
      _SessionCompleteScreenState();
}

class _SessionCompleteScreenState
    extends ConsumerState<SessionCompleteScreen> {
  final _durationCtrl = TextEditingController();
  final _distanceCtrl = TextEditingController();
  double _rpe         = 5;
  double _avgHR       = 0;
  double _maxHR       = 0;
  bool   _saving      = false;

  double _energyLevel = 3;
  double _perceived   = 3;
  String _notes       = '';

  bool _sensorDataAvailable = false;

  @override
  void initState() {
    super.initState();
    // Rellenar desde sensores tras el primer frame
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoFill());
  }

  void _autoFill() {
    final session = ref.read(activeSessionProvider);

    // Duración desde timer
    if (session.elapsedSeconds > 0) {
      _durationCtrl.text =
          (session.elapsedSeconds / 60).ceil().toString();
    }

    // Distancia desde GPS
    if (session.totalDistanceM > 0) {
      _distanceCtrl.text =
          (session.totalDistanceM / 1000).toStringAsFixed(2);
    }

    // FC desde BLE
    final hrAvg = session.hrAvg;
    final hrMax = session.hrMax;
    if (hrAvg != null && hrAvg > 0 || hrMax != null && hrMax > 0) {
      setState(() {
        _avgHR               = (hrAvg ?? 0).toDouble();
        _maxHR               = (hrMax ?? 0).toDouble();
        _sensorDataAvailable = true;
      });
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _durationCtrl.dispose();
    _distanceCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(activeSessionProvider.notifier).completeSession(
        widget.sessionId,
        {
          'actualDurationMin': int.tryParse(_durationCtrl.text),
          'actualDistanceM': _distanceCtrl.text.isNotEmpty
              ? ((double.tryParse(_distanceCtrl.text) ?? 0) * 1000).round()
              : null,
          'actualRpe': _rpe.round(),
          'actualHrAvgBpm': _avgHR > 0 ? _avgHR.round() : null,
          'actualHrMaxBpm': _maxHR > 0 ? _maxHR.round() : null,
          'athleteFeedback': {
            'energy_level':     _energyLevel.round(),
            'perceived_effort': _perceived.round(),
            'notes': _notes.isEmpty ? null : _notes,
          },
        },
      );
      if (mounted) {
        ref.read(dashboardProvider.notifier).load();
        context.go(AppRoutes.home);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = ref.watch(activeSkinProvider);

    return Scaffold(
      backgroundColor: skin.background,
      appBar: AppBar(
        backgroundColor: skin.backgroundSecondary,
        title: Text(
          '¿CÓMO FUE?',
          style: TextStyle(
              color: skin.textPrimary, letterSpacing: 2, fontSize: 14),
        ),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Banner sensor data ──────────────────────────
            if (_sensorDataAvailable)
              _SensorBanner(skin: skin),

            const SizedBox(height: 16),

            // ── Duración y Distancia ────────────────────────
            _SectionTitle('MÉTRICAS', skin),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _NumberField(
                    controller: _durationCtrl,
                    label: 'Duración (min)',
                    skin: skin,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _NumberField(
                    controller: _distanceCtrl,
                    label: 'Distancia (km)',
                    skin: skin,
                    decimal: true,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // ── RPE ─────────────────────────────────────────
            _SectionTitle('ESFUERZO PERCIBIDO (RPE)', skin),
            const SizedBox(height: 8),
            _RpeSlider(
                skin: skin,
                value: _rpe,
                onChanged: (v) => setState(() => _rpe = v)),

            const SizedBox(height: 24),

            // ── FC ───────────────────────────────────────────
            _SectionTitle(
              _sensorDataAvailable
                  ? 'FRECUENCIA CARDÍACA (desde sensor)'
                  : 'FRECUENCIA CARDÍACA',
              skin,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Media',
                          style: TextStyle(
                              color: skin.textMuted, fontSize: 12)),
                      Slider(
                        value: _avgHR,
                        min: 0,
                        max: 220,
                        divisions: 220,
                        activeColor: skin.accent,
                        inactiveColor: skin.border,
                        label:
                            _avgHR > 0 ? '${_avgHR.round()} bpm' : '--',
                        onChanged: (v) => setState(() => _avgHR = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Máxima',
                          style: TextStyle(
                              color: skin.textMuted, fontSize: 12)),
                      Slider(
                        value: _maxHR,
                        min: 0,
                        max: 220,
                        divisions: 220,
                        activeColor: skin.error,
                        inactiveColor: skin.border,
                        label:
                            _maxHR > 0 ? '${_maxHR.round()} bpm' : '--',
                        onChanged: (v) => setState(() => _maxHR = v),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // ── Sensaciones ─────────────────────────────────
            _SectionTitle('SENSACIONES', skin),
            const SizedBox(height: 8),
            _ScaleRow(
              label: 'Nivel de energía',
              value: _energyLevel,
              skin: skin,
              onChanged: (v) => setState(() => _energyLevel = v),
            ),
            _ScaleRow(
              label: 'Esfuerzo percibido',
              value: _perceived,
              skin: skin,
              onChanged: (v) => setState(() => _perceived = v),
            ),

            const SizedBox(height: 24),

            // ── Notas ────────────────────────────────────────
            _SectionTitle('NOTAS (opcional)', skin),
            const SizedBox(height: 8),
            TextField(
              onChanged: (v) => _notes = v,
              maxLines: 3,
              style: TextStyle(color: skin.textPrimary),
              decoration: InputDecoration(
                hintText: '¿Algo que destacar de la sesión?',
                hintStyle: TextStyle(color: skin.textMuted),
                filled: true,
                fillColor: skin.backgroundCard,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(skin.cardRadius),
                  borderSide: BorderSide(color: skin.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(skin.cardRadius),
                  borderSide: BorderSide(color: skin.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(skin.cardRadius),
                  borderSide:
                      BorderSide(color: skin.accent, width: 2),
                ),
              ),
            ),

            const SizedBox(height: 32),

            // ── Guardar ──────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? CircularProgressIndicator(
                        color: skin.background, strokeWidth: 2)
                    : const Text(
                        'GUARDAR SESIÓN',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, letterSpacing: 2),
                      ),
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ── Helpers ──────────────────────────────────────────────────────

class _SensorBanner extends StatelessWidget {
  final dynamic skin;
  const _SensorBanner({required this.skin});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: skin.success.withOpacity(0.12),
          borderRadius: BorderRadius.circular(skin.cardRadius),
          border: Border.all(color: skin.success.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.sensors, color: skin.success, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Datos de FC rellenados automáticamente desde el sensor. Puedes ajustarlos.',
                style: TextStyle(color: skin.success, fontSize: 12),
              ),
            ),
          ],
        ),
      );
}

class _SectionTitle extends StatelessWidget {
  final String text;
  final dynamic skin;
  const _SectionTitle(this.text, this.skin);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
            color: skin.textMuted, fontSize: 10, letterSpacing: 2),
      );
}

class _NumberField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool decimal;
  final dynamic skin;
  const _NumberField({
    required this.controller,
    required this.label,
    required this.skin,
    this.decimal = false,
  });

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        style: TextStyle(color: skin.textPrimary),
        decoration: InputDecoration(
          labelText: label,
          labelStyle:
              TextStyle(color: skin.textMuted, fontSize: 12),
          filled: true,
          fillColor: skin.backgroundCard,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(skin.cardRadius),
            borderSide: BorderSide(color: skin.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(skin.cardRadius),
            borderSide: BorderSide(color: skin.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(skin.cardRadius),
            borderSide: BorderSide(color: skin.accent, width: 2),
          ),
        ),
      );
}

class _RpeSlider extends StatelessWidget {
  final dynamic skin;
  final double value;
  final ValueChanged<double> onChanged;
  const _RpeSlider(
      {required this.skin, required this.value, required this.onChanged});

  String get _label {
    if (value <= 2) return 'Muy suave';
    if (value <= 4) return 'Suave';
    if (value <= 6) return 'Moderado';
    if (value <= 8) return 'Duro';
    return 'Máximo';
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${value.round()}',
                  style: TextStyle(
                      color: skin.accent,
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      fontFamily: skin.fontFamilyMono)),
              Text(_label,
                  style: TextStyle(
                      color: skin.textSecondary, fontSize: 14)),
            ],
          ),
          Slider(
            value: value,
            min: 1,
            max: 10,
            divisions: 9,
            activeColor: skin.accent,
            inactiveColor: skin.border,
            onChanged: onChanged,
          ),
        ],
      );
}

class _ScaleRow extends StatelessWidget {
  final String label;
  final double value;
  final dynamic skin;
  final ValueChanged<double> onChanged;
  const _ScaleRow(
      {required this.label,
      required this.value,
      required this.skin,
      required this.onChanged});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(label,
                style: TextStyle(
                    color: skin.textSecondary, fontSize: 13)),
          ),
          Expanded(
            flex: 3,
            child: Slider(
              value: value,
              min: 1,
              max: 5,
              divisions: 4,
              activeColor: skin.accentSecondary,
              inactiveColor: skin.border,
              label: value.round().toString(),
              onChanged: onChanged,
            ),
          ),
          Text('${value.round()}/5',
              style: TextStyle(
                  color: skin.textMuted,
                  fontSize: 12,
                  fontFamily: skin.fontFamilyMono)),
        ],
      );
}
