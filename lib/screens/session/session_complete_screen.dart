import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/skin_provider.dart';
import '../../providers/workout_provider.dart';
import '../../config/router.dart';
import '../../core/gps/gps_service.dart';
import '../../core/network/api_client.dart';
import '../../core/network/pending_tracks.dart';
import '../../widgets/route_map_widget.dart';
import 'hr_recovery_screen.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

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

  // Dictado por voz del comentario (motor del móvil, coste 0).
  // SIN límite de tiempo: lo termina EL DEPORTISTA (botón) o, tras ~7 s sin
  // oír voz, se le PREGUNTA si quiere terminar (antes cortaba solo a los 4 s
  // de pausa o a los 2 min — se quedaba corto a mitad de frase).
  final _notesCtrl = TextEditingController();
  final stt.SpeechToText _stt = stt.SpeechToText();
  bool   _sttReady    = false;
  bool   _listening   = false; // el MOTOR está escuchando ahora (segmento)
  bool   _dictating   = false; // el DEPORTISTA está dictando (hasta que él pare)
  bool   _askingStop  = false; // diálogo de silencio en pantalla
  String _notesBefore = '';
  Timer? _silenceTimer;

  bool _sensorDataAvailable = false;
  GpsTrack? _gpsTrack;

  @override
  void initState() {
    super.initState();
    // Rellenar desde sensores tras el primer frame
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoFill());
    // Preparar el dictado por voz (no pide permiso hasta que se pulsa el micro)
    _stt.initialize(
      onStatus: (s) {
        if (!mounted) return;
        if (s == 'done' || s == 'notListening') {
          setState(() => _listening = false);
          // El motor nativo de Android corta solo cada pocos segundos: si el
          // DEPORTISTA no ha terminado, se re-arma el siguiente segmento y el
          // texto se acumula → dictado continuo de verdad.
          if (_dictating && !_askingStop) _startSegment();
        }
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _listening = false);
        if (_dictating && !_askingStop) {
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted && _dictating && !_askingStop && !_listening) _startSegment();
          });
        }
      },
    ).then((ok) { if (mounted) setState(() => _sttReady = ok); }).catchError((_) {});
  }

  // Micrófono ON/OFF a voluntad del DEPORTISTA. El texto se AÑADE y queda editable.
  Future<void> _toggleDictation() async {
    if (_dictating) { await _stopDictation(); return; }
    if (!_sttReady) {
      final ok = await _stt.initialize().catchError((_) => false);
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Tu móvil no permite el dictado por voz (revisa el permiso de micrófono).')));
        }
        return;
      }
      _sttReady = true;
    }
    setState(() => _dictating = true);
    _armSilenceTimer();
    await _startSegment();
  }

  // Un "segmento" = una escucha del motor. Se encadenan hasta que el atleta pare.
  Future<void> _startSegment() async {
    if (!_dictating || _askingStop || _listening) return;
    // Lo ya reconocido (o tecleado) es la BASE: el segmento nuevo se añade encima.
    _notesBefore = _notesCtrl.text.trim();
    setState(() => _listening = true);
    await _stt.listen(
      listenOptions: stt.SpeechListenOptions(
        localeId: 'es_ES',
        listenFor: const Duration(minutes: 10), // techo de seguridad, NO el que corta
        pauseFor: const Duration(seconds: 8),   // si el motor corta antes, re-armamos
        partialResults: true,
        cancelOnError: true,
      ),
      onResult: (r) {
        final dictado = r.recognizedWords.trim();
        if (dictado.isNotEmpty) _armSilenceTimer(); // hay voz → reinicia el contador
        final texto = (_notesBefore.isEmpty ? dictado : '$_notesBefore $dictado').trim();
        _notes = texto;
        _notesCtrl.value = TextEditingValue(
          text: texto,
          selection: TextSelection.collapsed(offset: texto.length),
        );
      },
    );
  }

  void _armSilenceTimer() {
    _silenceTimer?.cancel();
    _silenceTimer = Timer(const Duration(seconds: 7), _askStopForSilence);
  }

  Future<void> _stopDictation() async {
    _silenceTimer?.cancel();
    _dictating = false;
    await _stt.stop();
    if (mounted) setState(() => _listening = false);
  }

  // ~7 s sin oír voz → se PREGUNTA (no se corta en seco). Si mientras tanto
  // vuelve a hablar, el texto sigue entrando; "Seguir" re-arma el contador.
  Future<void> _askStopForSilence() async {
    if (!mounted || !_dictating || _askingStop) return;
    _askingStop = true;
    final seguir = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Terminamos el dictado?'),
        content: const Text('Llevo unos segundos sin oírte. Si ya está todo dicho, '
            'lo dejamos aquí; el texto queda en el cuadro y puedes retocarlo.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Seguir dictando'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Terminar'),
          ),
        ],
      ),
    );
    _askingStop = false;
    if (!mounted) return;
    if (seguir == true && _dictating) {
      _armSilenceTimer();
      if (!_listening) _startSegment(); // por si el motor se durmió durante el diálogo
    } else {
      await _stopDictation();
    }
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

    // GPS track (guardado por stopGPS en la pantalla de sesión)
    final track = session.completedTrack;
    if (track != null && track.points.length >= 2) {
      setState(() => _gpsTrack = track);
    }
  }

  @override
  void dispose() {
    _silenceTimer?.cancel();
    _dictating = false;
    _durationCtrl.dispose();
    _distanceCtrl.dispose();
    _notesCtrl.dispose();
    _stt.stop();
    super.dispose();
  }

  Future<void> _save() async {
    // Teclado español = COMA decimal ("7,86"). double.tryParse la rechazaba y el
    // `?? 0` convertía la distancia en 0 km EN SILENCIO (kilómetros perdidos).
    // Normalizamos coma→punto y, si aun así no es número, avisamos sin guardar.
    double? parseNum(String s) => double.tryParse(s.trim().replaceAll(',', '.'));
    final durVal  = _durationCtrl.text.trim().isEmpty ? null : parseNum(_durationCtrl.text);
    final distKm  = _distanceCtrl.text.trim().isEmpty ? null : parseNum(_distanceCtrl.text);
    if ((_durationCtrl.text.trim().isNotEmpty && durVal == null) ||
        (_distanceCtrl.text.trim().isNotEmpty && distKm == null)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Revisa duración/distancia: usa solo números (ej. 45 o 7,86).')));
      return;
    }
    setState(() => _saving = true);
    try {
      // v7.2: la subida del track ya NO falla en silencio. Antes un catch vacio
      // se tragaba el error, completeSession triunfaba y el entreno quedaba
      // "guardado" sin recorrido — perdida invisible. Ahora se reintenta y, si no
      // hay manera, el atleta DECIDE (reintentar o guardar sin recorrido).
      var trackSubido = !(_gpsTrack != null && _gpsTrack!.points.length >= 2);
      // EL RECORRIDO SE ESCRIBE EN EL MÓVIL ANTES DE INTENTAR SUBIRLO.
      //
      // El 20/07 un atleta caminó 562 m, el servidor devolvió un 500 y al salir
      // de esta pantalla el recorrido se perdió entero: vivía solo en memoria.
      // Ahora se queda en el teléfono hasta que el servidor confirme que lo
      // tiene, y se reintenta solo al abrir la app.
      if (!trackSubido) {
        await PendingTracks.guardar(widget.sessionId, _gpsTrack!.toBackendPayload());
      }
      var intentos = 0;
      while (!trackSubido && intentos < 3) {
        intentos++;
        try {
          await ref.read(apiClientProvider).postGPSTrack(
            widget.sessionId,
            _gpsTrack!.toBackendPayload(),
          );
          trackSubido = true;
          await PendingTracks.borrar(widget.sessionId);   // confirmado por el servidor
        } catch (_) {
          if (!mounted) break;
          final reintentar = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('No se pudo subir el recorrido'),
              content: const Text(
                  'No he podido subir el recorrido ahora mismo.\n\n'
                  'Tranquilo: se ha guardado en el móvil y lo subiré solo la '
                  'próxima vez que abras la app con conexión. No vas a perder '
                  'tus kilómetros.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Continuar'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          );
          if (reintentar != true) break;
        }
      }

      await ref.read(activeSessionProvider.notifier).completeSession(
        widget.sessionId,
        {
          'actualDurationMin': durVal?.round(),
          'actualDistanceM': distKm != null ? (distKm * 1000).round() : null,
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
            // ── Mapa de ruta ────────────────────────────────
            if (_gpsTrack != null && _gpsTrack!.points.length >= 2) ...[
              _SectionTitle('RECORRIDO', skin),
              const SizedBox(height: 8),
              RouteMapWidget(
                points: _gpsTrack!.points,
                maxHR: _maxHR > 0 ? _maxHR.round() : null,
              ),
              const SizedBox(height: 16),
            ],

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

            // ── Notas (escribe o DICTA por voz — coste 0) ────
            Row(
              children: [
                Expanded(child: _SectionTitle('NOTAS (opcional)', skin)),
                if (_sttReady)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: _toggleDictation,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: (_dictating ? Colors.red : skin.accent).withValues(alpha: _dictating ? 0.15 : 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: (_dictating ? Colors.red : skin.accent).withValues(alpha: 0.4)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(_dictating ? Icons.stop_rounded : Icons.mic_rounded,
                              size: 16, color: _dictating ? Colors.red : skin.accent),
                          const SizedBox(width: 5),
                          Text(_dictating ? 'Terminar' : 'Dictar',
                              style: TextStyle(
                                  color: _dictating ? Colors.red : skin.accent,
                                  fontSize: 12.5, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notesCtrl,
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

            // ── Recuperación cardíaca (solo con BLE conectado) ──
            if (ref.read(activeSessionProvider).bleConnected) ...[
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: skin.error,
                    side: BorderSide(
                        color: skin.error.withValues(alpha: 0.6), width: 1.2),
                  ),
                  icon: Icon(Icons.favorite, size: 18, color: skin.error),
                  label: const Text(
                    'Medir recuperación cardíaca',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            HrRecoveryScreen(sessionId: widget.sessionId),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],

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
          color: skin.success.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(skin.cardRadius),
          border: Border.all(color: skin.success.withValues(alpha: 0.3)),
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
