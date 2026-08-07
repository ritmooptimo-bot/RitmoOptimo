import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/skin_provider.dart';
import '../../core/network/api_client.dart';
import '../../core/notifications/notification_service.dart';
import '../../widgets/boton_ajustes.dart';
import 'hrv_camera_screen.dart';
import 'hrv_band_screen.dart';

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
  String _hrvMethod = 'manual'; // manual | camera | band (según cómo se midió)

  bool _saving   = false;
  bool _done     = false;
  bool _editing  = false;   // en modo edición del check-in ya hecho
  bool _loadingToday = true; // cargando el check-in de hoy (ficha vs formulario)

  // "Estado de hoy": si ya hay check-in hoy, al guardar avisamos de sobrescritura.
  Map<String, dynamic>? _todayReadiness;

  @override
  void initState() {
    super.initState();
    _loadTodayReadiness();
  }

  Future<void> _loadTodayReadiness() async {
    try {
      final r = await ref.read(apiClientProvider).getWellnessToday();
      if (!mounted) return;
      setState(() {
        _loadingToday = false;
        _todayReadiness = r;
        // Una medición al día: si ya hay check-in de hoy, pre-rellenamos el
        // formulario con lo guardado (sliders + HRV/FC medidos hoy), no defaults.
        // Así el deportista ve lo suyo y, si lo cambia, se le avisa de sobrescritura.
        if (r['doneToday'] == true) {
          final f = r['fatigue'], m = r['mood'], mo = r['motivation'];
          final sh = r['sleep_hours'], sq = r['sleep_quality'];
          if (f is num)  _fatigue    = f.toDouble();
          if (m is num)  _mood       = m.toDouble();
          if (mo is num) _motivation = mo.toDouble();
          if (sh is num) _sleepH     = sh.toDouble();
          if (sq is num) _sleepQ     = sq.toDouble();
          if (r['hrv_ms'] is num)         _hrvCtrl.text = (r['hrv_ms'] as num).round().toString();
          if (r['resting_hr_bpm'] is num) _hrCtrl.text  = (r['resting_hr_bpm'] as num).round().toString();
          if (r['measurement_method'] is String) _hrvMethod = r['measurement_method'] as String;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _loadingToday = false);
    }
  }

  @override
  void dispose() {
    _hrvCtrl.dispose();
    _hrCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    // Una medición al día: si ya hay check-in de hoy, editor con aviso de
    // sobrescritura (con sus pros y contras) antes de pisar el dato.
    if (_todayReadiness?['doneToday'] == true) {
      final ok = await _confirmOverwrite();
      if (ok != true) return;
    }
    // Los teclados en español usan COMA decimal ("19,5"): double.tryParse la
    // rechaza → el HRV se guardaba como null EN SILENCIO. Normalizamos y, si aun
    // así no es un número, avisamos y NO guardamos a medias.
    double? parseNum(String s) => double.tryParse(s.trim().replaceAll(',', '.'));
    final hrvVal = _hrvCtrl.text.trim().isEmpty ? null : parseNum(_hrvCtrl.text);
    final hrVal  = _hrCtrl.text.trim().isEmpty ? null : parseNum(_hrCtrl.text);
    if ((_hrvCtrl.text.trim().isNotEmpty && hrvVal == null) ||
        (_hrCtrl.text.trim().isNotEmpty && hrVal == null)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Revisa el HRV/FC: usa solo números (ej. 54 o 54,5).')));
      }
      return;
    }
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

      // HRV si se introdujo (valores ya validados y con coma normalizada)
      if (hrvVal != null || hrVal != null) {
        await api.postHRV({
          if (hrvVal != null) 'hrv_ms': hrvVal,
          if (hrVal != null) 'resting_hr_bpm': hrVal.round(),
          'sleep_hours':  _sleepH,
          'sleep_quality': _sleepQ.round(),
          'measurement_method': _hrvMethod,
        });
      }

      // El check-in de HOY ya está hecho → retira la notificación fija del día.
      await NotificationService.completedToday();

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

  // Editor/advertencia de sobrescritura: solo hay UN check-in por día; si ya
  // existe el de hoy, mostramos qué se va a guardar + pros y contras.
  Future<bool?> _confirmOverwrite() {
    final skin  = ref.read(activeSkinProvider);
    final label = _todayReadiness?['label'] as String?;
    final score = _todayReadiness?['score'];
    String n(double x) => x.round().toString();
    String h(double x) => x % 1 == 0 ? x.toInt().toString() : x.toStringAsFixed(1);
    String metodo() {
      switch (_hrvMethod) {
        case 'ble':
        case 'band':
          return 'banda';
        case 'camera_ppg':
        case 'camera':
          return 'cámara';
        default:
          return 'manual';
      }
    }
    final nuevos = <String>[
      'Fatiga: ${n(_fatigue)}/5',
      'Ánimo: ${n(_mood)}/5',
      'Motivación: ${n(_motivation)}/5',
      'Sueño: ${h(_sleepH)} h · calidad ${n(_sleepQ)}/5',
      if (_hrvCtrl.text.isNotEmpty) 'HRV: ${_hrvCtrl.text} ms (${metodo()})',
      if (_hrCtrl.text.isNotEmpty)  'FC reposo: ${_hrCtrl.text} ppm',
    ];
    final actual = label == null
        ? 'Ya tienes un check-in guardado hoy.'
        : (score != null
            ? 'Estado actual de hoy: $label · $score/100.'
            : 'Estado actual de hoy: $label.');

    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: skin.backgroundCard,
        title: Row(children: [
          Icon(Icons.warning_amber_rounded, color: skin.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Sobrescribir el check-in de hoy',
                style: TextStyle(color: skin.textPrimary, fontSize: 17)),
          ),
        ]),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Solo se guarda una medición por día. $actual',
                  style: TextStyle(color: skin.textSecondary, fontSize: 13.5)),
              const SizedBox(height: 12),
              Text('Se guardará (y reemplaza lo de hoy):',
                  style: TextStyle(
                      color: skin.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
              const SizedBox(height: 6),
              ...nuevos.map((s) => Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text('•  $s',
                        style:
                            TextStyle(color: skin.textSecondary, fontSize: 13)),
                  )),
              const SizedBox(height: 14),
              Text('✅  Útil si te equivocaste al meter un dato.',
                  style: TextStyle(color: skin.success, fontSize: 12.5)),
              const SizedBox(height: 4),
              Text(
                  '⚠️  Pierdes la lectura anterior. Si esta es de peor calidad '
                  '(p. ej. HRV por cámara sobre una lectura de banda) empeoras '
                  'el dato del día.',
                  style: TextStyle(color: skin.warning, fontSize: 12.5)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar', style: TextStyle(color: skin.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: skin.warning),
            child: const Text('Sobrescribir'),
          ),
        ],
      ),
    );
  }

  // Ficha de SOLO LECTURA del check-in ya hecho hoy: el deportista ve lo que
  // rellenó sin poder tocar nada, y abajo un botón para modificarlo (con aviso).
  Widget _buildFicha(dynamic skin) {
    final r = _todayReadiness ?? {};
    String n(dynamic x) => x is num ? x.round().toString() : '—';
    String h(dynamic x) {
      if (x is! num) return '—';
      return x % 1 == 0 ? x.toInt().toString() : x.toStringAsFixed(1);
    }
    String metodo() {
      switch (_hrvMethod) {
        case 'ble':
        case 'band':
          return 'banda';
        case 'camera_ppg':
        case 'camera':
          return 'cámara';
        default:
          return 'manual';
      }
    }
    final hrv = r['hrv_ms'], fc = r['resting_hr_bpm'];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ReadinessBanner(skin: skin),
          Text('Tu check-in de hoy',
              style: TextStyle(
                  color: skin.textPrimary, fontSize: 22, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text('Ya registrado. Estos son los datos que guardaste hoy.',
              style: TextStyle(color: skin.textMuted, fontSize: 13)),
          const SizedBox(height: 20),
          _fichaRow(skin, '⚡', 'Fatiga', '${n(r['fatigue'])}/5'),
          _fichaRow(skin, '😊', 'Estado de ánimo', '${n(r['mood'])}/5'),
          _fichaRow(skin, '🔥', 'Motivación', '${n(r['motivation'])}/5'),
          _fichaRow(skin, '😴', 'Sueño',
              '${h(r['sleep_hours'])} h · calidad ${n(r['sleep_quality'])}/5'),
          if (hrv is num) _fichaRow(skin, '❤️', 'HRV', '${hrv.round()} ms · ${metodo()}'),
          if (fc is num) _fichaRow(skin, '🫀', 'FC en reposo', '${fc.round()} ppm'),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              onPressed: () => setState(() => _editing = true),
              style: OutlinedButton.styleFrom(
                foregroundColor: skin.accent,
                side: BorderSide(color: skin.accent),
              ),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('MODIFICAR',
                  style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1.5)),
            ),
          ),
          const SizedBox(height: 8),
          Text('Al modificar se sobrescribe el registro de hoy; te avisaremos antes.',
              textAlign: TextAlign.center,
              style: TextStyle(color: skin.textMuted, fontSize: 12)),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _fichaRow(dynamic skin, String emoji, String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: skin.backgroundCard,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: skin.textSecondary, fontSize: 15)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.end,
                style: TextStyle(
                    color: skin.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final skin = ref.watch(activeSkinProvider);

    return Scaffold(
      backgroundColor: skin.background,
      appBar: AppBar(
        backgroundColor: skin.backgroundSecondary,
        title: Text('Check-in diario',
            style: TextStyle(color: skin.textPrimary, fontSize: 16,
                fontWeight: FontWeight.w700)),
        actions: const [BotonAjustes()],
      ),
      body: _done
          ? _DoneView(skin: skin)
          : _loadingToday
          ? Center(child: CircularProgressIndicator(color: skin.accent))
          : (_todayReadiness?['doneToday'] == true && !_editing)
          // Ya hecho hoy → ficha de solo lectura + botón Modificar.
          ? _buildFicha(skin)
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Estado de hoy / recordatorio (hecho o pendiente).
                  _ReadinessBanner(skin: skin),

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

                  // Edad + VO2max estimado (referencias) — arriba, antes de medir HRV
                  _FitnessCard(skin: skin),

                  const SizedBox(height: 16),

                  // HRV Opcional
                  _HRVCard(
                      skin: skin,
                      hrvCtrl: _hrvCtrl,
                      hrCtrl: _hrCtrl,
                      onMethod: (m) => _hrvMethod = m),

                  const SizedBox(height: 12),

                  // HRV vs línea base de 7 días (estado de recuperación)
                  _HrvBaselineCard(skin: skin),

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

// Banner de "Estado de hoy": si ya hizo el check-in muestra el veredicto y
// "vuelve mañana"; si no, invita a rellenarlo (antes de entrenar).
class _ReadinessBanner extends ConsumerStatefulWidget {
  final dynamic skin;
  const _ReadinessBanner({required this.skin});
  @override
  ConsumerState<_ReadinessBanner> createState() => _ReadinessBannerState();
}

class _ReadinessBannerState extends ConsumerState<_ReadinessBanner> {
  Map<String, dynamic>? _r;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await ref.read(apiClientProvider).getReadiness();
      if (mounted) setState(() {
        _r = r;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    final r = _r;
    if (_loading || r == null) return const SizedBox.shrink();
    final done = r['doneToday'] == true;
    if (!done) {
      return _wrap(skin, skin.accent, Icons.today,
          'Aún no has hecho tu check-in de hoy',
          'Rellénalo abajo (2 min), mejor antes de entrenar: tu plan se adapta a cómo estás.');
    }
    final status = r['status'] as String? ?? 'yellow';
    Color color;
    switch (status) {
      case 'green':
        color = skin.success;
        break;
      case 'red':
        color = skin.error;
        break;
      default:
        color = skin.warning;
    }
    final label = r['label'] as String? ?? 'Estado de hoy';
    final advice = r['advice'] as String? ?? '';
    return _wrap(skin, color, Icons.check_circle, 'Hecho hoy · $label',
        '$advice\nYa registrado — mañana toca el siguiente.');
  }

  Widget _wrap(dynamic skin, Color color, IconData icon, String title,
      String sub) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: color,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(sub,
                      style: TextStyle(
                          color: skin.textSecondary,
                          fontSize: 12,
                          height: 1.3)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Estado del HRV de hoy vs la línea base de 7 días (GET /athlete/hrv-baseline).
class _HrvBaselineCard extends ConsumerStatefulWidget {
  final dynamic skin;
  const _HrvBaselineCard({required this.skin});
  @override
  ConsumerState<_HrvBaselineCard> createState() => _HrvBaselineCardState();
}

class _HrvBaselineCardState extends ConsumerState<_HrvBaselineCard> {
  Map<String, dynamic>? _b;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final b = await ref.read(apiClientProvider).getHrvBaseline();
      if (mounted) setState(() {
        _b = b;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    final b = _b;
    if (_loading || b == null) return const SizedBox.shrink();
    final status = b['status'] as String? ?? 'no_data';
    if (status == 'no_data') return const SizedBox.shrink();

    if (status == 'establishing') {
      final n = b['nDays'] ?? 0;
      final need = b['daysNeeded'] ?? 7;
      return _wrap(skin, skin.textMuted, Icons.timelapse,
          'Estableciendo tu HRV base ($n/$need días)',
          'Mide a la misma hora cada día. En unos días verás si hoy estás por encima o por debajo de tu normal.');
    }

    final today = b['todayRmssd'];
    final base = b['baselineRmssd'];
    final Color color;
    final IconData icon;
    final String title;
    final String sub;
    switch (status) {
      case 'low':
        color = skin.error;
        icon = Icons.trending_down;
        title = 'HRV por debajo de tu media';
        sub =
            'Hoy $today vs ~$base ms. Tu cuerpo acusa carga o estrés: prioriza recuperar.';
        break;
      case 'high':
        color = skin.success;
        icon = Icons.trending_up;
        title = 'HRV por encima de tu media';
        sub = 'Hoy $today vs ~$base ms. Buena señal de recuperación.';
        break;
      default:
        color = skin.accent;
        icon = Icons.check_circle_outline;
        title = 'HRV en tu rango normal';
        sub = 'Hoy $today vs ~$base ms. Todo estable.';
    }
    return _wrap(skin, color, icon, title, sub);
  }

  Widget _wrap(dynamic skin, Color color, IconData icon, String title,
      String sub) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: color,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(sub,
                      style: TextStyle(
                          color: skin.textSecondary,
                          fontSize: 12,
                          height: 1.3)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Edad (con captura de fecha de nacimiento si falta) + VO2max estimado.
class _FitnessCard extends ConsumerStatefulWidget {
  final dynamic skin;
  const _FitnessCard({required this.skin});
  @override
  ConsumerState<_FitnessCard> createState() => _FitnessCardState();
}

class _FitnessCardState extends ConsumerState<_FitnessCard> {
  Map<String, dynamic>? _basics;
  Map<String, dynamic>? _vo2;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final basics = await ref.read(apiClientProvider).getProfileBasics();
      Map<String, dynamic>? vo2;
      if (basics['age'] != null) {
        vo2 = await ref
            .read(apiClientProvider)
            .getVo2max()
            .catchError((_) => <String, dynamic>{});
      }
      if (mounted) {
        setState(() {
          _basics = basics;
          _vo2 = vo2;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 30, 1, 1),
      firstDate: DateTime(now.year - 100),
      lastDate: DateTime(now.year - 5),
      helpText: 'Tu fecha de nacimiento',
    );
    if (picked == null) return;
    final iso =
        '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    try {
      await ref.read(apiClientProvider).saveBirthDate(iso);
      setState(() => _loading = true);
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudo guardar la fecha')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    if (_loading) return const SizedBox.shrink();
    final age = _basics?['age'];

    // Sin edad → invitación a completarla (para VO2max y referencias).
    if (age == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(Icons.cake_outlined, color: skin.accent, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Añade tu fecha de nacimiento',
                        style: TextStyle(
                            color: skin.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                        'Con tu edad calculamos tu VO2max estimado y tus referencias por edad.',
                        style: TextStyle(
                            color: skin.textSecondary,
                            fontSize: 12,
                            height: 1.3)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _pickBirthDate,
                child: Text('Añadir', style: TextStyle(color: skin.accent)),
              ),
            ],
          ),
        ),
      );
    }

    // Con edad → edad editable + VO2max estimado.
    final vo2 = _vo2;
    String? vo2Line;
    if (vo2 != null && vo2['status'] == 'ok') {
      vo2Line =
          'VO₂max estimado ~${vo2['vo2max']} ml/kg/min · ${vo2['category']}';
    } else if (vo2 != null && vo2['status'] == 'need_resting_hr') {
      vo2Line = 'Mide tu FC en reposo (arriba) para estimar tu VO₂max.';
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.fitness_center, color: skin.accent, size: 22),
                const SizedBox(width: 10),
                Text('$age años',
                    style: TextStyle(
                        color: skin.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                InkWell(
                  onTap: _pickBirthDate,
                  child: Row(children: [
                    Icon(Icons.edit, size: 14, color: skin.textMuted),
                    const SizedBox(width: 4),
                    Text('Editar',
                        style: TextStyle(color: skin.textMuted, fontSize: 12)),
                  ]),
                ),
              ],
            ),
            if (vo2Line != null) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.favorite_border, color: skin.error, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(vo2Line,
                        style: TextStyle(
                            color: skin.textSecondary,
                            fontSize: 12.5,
                            height: 1.3)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('Estimación a partir de tu FC en reposo y tu edad.',
                  style: TextStyle(color: skin.textMuted, fontSize: 11)),
            ],
          ],
        ),
      ),
    );
  }
}

class _HRVCard extends StatelessWidget {
  final dynamic skin;
  final TextEditingController hrvCtrl;
  final TextEditingController hrCtrl;
  final ValueChanged<String>? onMethod;
  const _HRVCard(
      {required this.skin,
      required this.hrvCtrl,
      required this.hrCtrl,
      this.onMethod});

  // Selector Cámara / Banda de pecho → abre la pantalla → rellena los campos.
  Future<void> _openMeasure(BuildContext context) async {
    final source = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: skin.backgroundSecondary,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: skin.textMuted.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              Text('¿Cómo quieres medir tu HRV?',
                  style: TextStyle(
                      color: skin.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              _sourceTile(ctx, Icons.monitor_heart_outlined, 'Banda de pecho',
                  'Intervalos R-R reales', 'ble',
                  recommended: true),
              const SizedBox(height: 10),
              _sourceTile(ctx, Icons.camera_alt_outlined, 'Cámara + flash',
                  'Estimación rápida, sin accesorios', 'camera_ppg'),
            ],
          ),
        ),
      ),
    );
    if (source == null || !context.mounted) return;
    Map? res;
    if (source == 'camera_ppg') {
      res = await Navigator.of(context).push<Map>(
          MaterialPageRoute(builder: (_) => const HrvCameraScreen()));
    } else if (source == 'ble') {
      res = await Navigator.of(context)
          .push<Map>(MaterialPageRoute(builder: (_) => const HrvBandScreen()));
    }
    if (res != null) {
      if (res['hrv'] != null) hrvCtrl.text = '${res['hrv']}';
      if (res['hr'] != null) hrCtrl.text = '${res['hr']}';
      onMethod?.call(res['method'] as String? ?? source);
    }
  }

  Widget _sourceTile(BuildContext ctx, IconData icon, String title,
      String subtitle, String value,
      {bool recommended = false}) {
    return InkWell(
      onTap: () => Navigator.of(ctx).pop(value),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: skin.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: recommended
                  ? skin.accent
                  : skin.textMuted.withValues(alpha: 0.25),
              width: recommended ? 2 : 1),
        ),
        child: Row(
          children: [
            Icon(icon, color: skin.accent, size: 30),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: skin.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (recommended) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                              color: skin.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8)),
                          child: Text('preciso',
                              style: TextStyle(
                                  color: skin.accent,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style:
                                TextStyle(color: skin.textMuted, fontSize: 12)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: skin.textMuted, size: 20),
          ],
        ),
      ),
    );
  }

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
                Flexible(
                  child: Text('HRV matutino (opcional)',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: skin.textPrimary, fontWeight: FontWeight.w600)),
                ),
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
              const SizedBox(height: 12),
              // Medir HRV/FC: elige cámara (estimación) o banda de pecho (preciso).
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _openMeasure(context),
                  icon: Icon(Icons.favorite_border, size: 18, color: skin.accent),
                  label:
                      Text('Medir HRV', style: TextStyle(color: skin.accent)),
                ),
              ),
            ],
          ),
        ),
      );
}
