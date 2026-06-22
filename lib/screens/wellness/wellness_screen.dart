import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/skin_provider.dart';
import '../../core/network/api_client.dart';

// ── Wellness Screen ──────────────────────────────────────────────
// Check-in diario de bienestar + registro HRV matutino.
// POST /wellness + POST /hrv → dispara evaluateWellness() automáticamente.

class WellnessScreen extends ConsumerStatefulWidget {
  const WellnessScreen({super.key});

  @override
  ConsumerState<WellnessScreen> createState() => _WellnessScreenState();
}

class _WellnessScreenState extends ConsumerState<WellnessScreen> {
  double _fatigue    = 3;
  double _mood       = 3;
  double _motivation = 3;
  double _sleepH     = 7;
  double _sleepQ     = 3;

  // HRV opcional
  final _hrvCtrl = TextEditingController();
  final _hrCtrl  = TextEditingController();

  bool _saving   = false;
  bool _done     = false;

  @override
  void dispose() {
    _hrvCtrl.dispose();
    _hrCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final api = ref.read(apiClientProvider);

      // Wellness check-in (siempre)
      await api.postWellness({
        'fatigue_level':  _fatigue.round(),
        'mood':           _mood.round(),
        'motivation':     _motivation.round(),
        'sleep_hours':    _sleepH,
        'sleep_quality':  _sleepQ.round(),
        'recorded_date':  DateTime.now().toIso8601String().split('T')[0],
      });

      // HRV si se introdujo
      if (_hrvCtrl.text.isNotEmpty || _hrCtrl.text.isNotEmpty) {
        await api.postHRV({
          if (_hrvCtrl.text.isNotEmpty)
            'hrv_ms': double.tryParse(_hrvCtrl.text),
          if (_hrCtrl.text.isNotEmpty)
            'resting_hr_bpm': int.tryParse(_hrCtrl.text),
          'sleep_hours':  _sleepH,
          'sleep_quality': _sleepQ.round(),
          'measurement_method': 'manual',
        });
      }

      setState(() { _done = true; _saving = false; });
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = ref.watch(activeSkinProvider);

    return Scaffold(
      backgroundColor: skin.background,
      appBar: AppBar(
        backgroundColor: skin.backgroundSecondary,
        title: Text('CHECK-IN DIARIO',
            style: TextStyle(color: skin.textPrimary, letterSpacing: 2, fontSize: 14)),
      ),
      body: _done
          ? _DoneView(skin: skin)
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '¿Cómo te encuentras hoy?',
                    style: TextStyle(
                        color: skin.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 24),

                  _ScaleCard(
                    label: 'Fatiga', emoji: '⚡',
                    value: _fatigue,
                    skin: skin,
                    onChanged: (v) => setState(() => _fatigue = v),
                    lowLabel: 'Fresco', highLabel: 'Agotado',
                  ),
                  _ScaleCard(
                    label: 'Estado de ánimo', emoji: '😊',
                    value: _mood,
                    skin: skin,
                    onChanged: (v) => setState(() => _mood = v),
                    lowLabel: 'Bajo', highLabel: 'Excelente',
                  ),
                  _ScaleCard(
                    label: 'Motivación', emoji: '🔥',
                    value: _motivation,
                    skin: skin,
                    onChanged: (v) => setState(() => _motivation = v),
                    lowLabel: 'Sin ganas', highLabel: 'Con ganas',
                  ),

                  const SizedBox(height: 16),

                  // Sueño
                  _SleepCard(
                    skin: skin,
                    hours: _sleepH,
                    quality: _sleepQ,
                    onHoursChanged: (v) => setState(() => _sleepH = v),
                    onQualityChanged: (v) => setState(() => _sleepQ = v),
                  ),

                  const SizedBox(height: 16),

                  // HRV Opcional
                  _HRVCard(skin: skin, hrvCtrl: _hrvCtrl, hrCtrl: _hrCtrl),

                  const SizedBox(height: 32),

                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? CircularProgressIndicator(
                              color: skin.background, strokeWidth: 2)
                          : const Text('GUARDAR CHECK-IN',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2)),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}

class _DoneView extends StatelessWidget {
  final dynamic skin;
  const _DoneView({required this.skin});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, color: skin.success, size: 80),
            const SizedBox(height: 16),
            Text('Check-in guardado',
                style: TextStyle(
                    color: skin.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('Tu entrenador IA ya tiene en cuenta\ncómo te encuentras hoy.',
                textAlign: TextAlign.center,
                style: TextStyle(color: skin.textMuted, fontSize: 14)),
          ],
        ),
      );
}

class _ScaleCard extends StatelessWidget {
  final String label;
  final String emoji;
  final double value;
  final dynamic skin;
  final ValueChanged<double> onChanged;
  final String lowLabel;
  final String highLabel;
  const _ScaleCard({
    required this.label, required this.emoji, required this.value,
    required this.skin, required this.onChanged,
    required this.lowLabel, required this.highLabel,
  });

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Text(label, style: TextStyle(
                      color: skin.textPrimary, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text('${value.round()}/5',
                      style: TextStyle(
                          color: skin.accent,
                          fontWeight: FontWeight.w700,
                          fontFamily: skin.fontFamilyMono)),
                ],
              ),
              Slider(
                value: value, min: 1, max: 5, divisions: 4,
                activeColor: skin.accent, inactiveColor: skin.border,
                onChanged: onChanged,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(lowLabel, style: TextStyle(color: skin.textMuted, fontSize: 11)),
                  Text(highLabel, style: TextStyle(color: skin.textMuted, fontSize: 11)),
                ],
              ),
            ],
          ),
        ),
      );
}

class _SleepCard extends StatelessWidget {
  final dynamic skin;
  final double hours;
  final double quality;
  final ValueChanged<double> onHoursChanged;
  final ValueChanged<double> onQualityChanged;
  const _SleepCard({
    required this.skin, required this.hours, required this.quality,
    required this.onHoursChanged, required this.onQualityChanged,
  });

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Text('🌙', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Text('Sueño', style: TextStyle(
                    color: skin.textPrimary, fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Text('Horas: ', style: TextStyle(color: skin.textMuted, fontSize: 13)),
                Text('${hours.toStringAsFixed(1)}h',
                    style: TextStyle(color: skin.accentSecondary,
                        fontWeight: FontWeight.w700,
                        fontFamily: skin.fontFamilyMono)),
              ]),
              Slider(value: hours, min: 0, max: 12, divisions: 24,
                  activeColor: skin.accentSecondary, inactiveColor: skin.border,
                  onChanged: onHoursChanged),
              Row(children: [
                Text('Calidad: ', style: TextStyle(color: skin.textMuted, fontSize: 13)),
                Text('${quality.round()}/5',
                    style: TextStyle(color: skin.accentSecondary,
                        fontWeight: FontWeight.w700,
                        fontFamily: skin.fontFamilyMono)),
              ]),
              Slider(value: quality, min: 1, max: 5, divisions: 4,
                  activeColor: skin.accentSecondary, inactiveColor: skin.border,
                  onChanged: onQualityChanged),
            ],
          ),
        ),
      );
}

class _HRVCard extends StatelessWidget {
  final dynamic skin;
  final TextEditingController hrvCtrl;
  final TextEditingController hrCtrl;
  const _HRVCard({required this.skin, required this.hrvCtrl, required this.hrCtrl});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Text('💓', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Text('HRV matutino (opcional)',
                    style: TextStyle(
                        color: skin.textPrimary, fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: TextField(
                  controller: hrvCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(color: skin.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'HRV (ms)',
                    labelStyle: TextStyle(color: skin.textMuted, fontSize: 12),
                    filled: true, fillColor: skin.backgroundSecondary,
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
                )),
                const SizedBox(width: 12),
                Expanded(child: TextField(
                  controller: hrCtrl,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: skin.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'FC reposo (bpm)',
                    labelStyle: TextStyle(color: skin.textMuted, fontSize: 12),
                    filled: true, fillColor: skin.backgroundSecondary,
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
                      borderSide: BorderSide(color: skin.border),
                    ),
                  ),
                )),
              ]),
            ],
          ),
        ),
      );
}
