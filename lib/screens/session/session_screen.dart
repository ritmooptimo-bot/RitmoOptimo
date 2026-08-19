import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../providers/skin_provider.dart';
import '../../models/ejercicio.dart';
import 'fuerza_session_screen.dart';
import '../../providers/workout_provider.dart';
import '../../config/skins/skin_config.dart';
import '../../core/network/api_client.dart';
import '../../core/ble/ble_service.dart';
import '../../core/gps/gps_service.dart';
import '../../models/sport.dart';
import '../../core/utils/zona_fc.dart';
import '../../providers/zonas_fc_provider.dart';
import 'voice_picker_sheet.dart';
import '../../core/audio/audio_cue_service.dart';
import '../../core/audio/session_audio_controller.dart';
import 'block_progress_widget.dart';
import 'interval_rep_widget.dart';
import '../../core/session/resumen_bloque.dart';

class SessionScreen extends ConsumerStatefulWidget {
  final String sessionId;
  const SessionScreen({super.key, required this.sessionId});

  @override
  ConsumerState<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends ConsumerState<SessionScreen> {
  Timer? _timer;
  bool _loadingSession = true; // true hasta que loadSession() devuelva datos
  // GPS live map
  final List<GpsPoint> _mapPoints = [];
  late final MapController _mapController;
  StreamSubscription<GpsPoint>? _gpsMapSub;
  bool _mapReady = false;
  bool _gpsOff = false;          // v7.2: sin GPS confirmado → banner rojo permanente
  bool _sinGpsPorDeporte = false; // fuerza o piscina: no hay recorrido que grabar (y está bien)
  double? _precisionM;            // precisión de la última lectura GPS (metros)
  StreamSubscription<double>? _precSub;
  // Audio-Guided Session (AGS)
  final AudioCueService _audioCueService = AudioCueService();
  SessionAudioController? _audioController;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        await ref.read(activeSessionProvider.notifier).loadSession(widget.sessionId);
        if (mounted) {
          setState(() => _loadingSession = false);
          _initAudioController();
          // REENTRAR EN UNA SESIÓN EN MARCHA. El cronómetro solo arrancaba desde
          // el botón COMENZAR, que ya no está visible si la sesión corre: al
          // volver a entrar el tiempo se quedaba clavado y la duración que se
          // autorrellenaba al terminar era falsa. Se reengancha el reloj.
          if (ref.read(activeSessionProvider).isRunning) _startTimer();
        }
      }
    });
  }

  void _initAudioController() {
    final blocks = ref.read(activeSessionProvider).session?['planned_structure'] as List<dynamic>?;
    if (blocks != null && blocks.isNotEmpty && _audioController == null) {
      // Las zonas en pulsaciones, si se han podido cargar. Si no, el aviso de
      // zona simplemente no existe: nunca se inventa un rango.
      final zonas = ref.read(zonasFcProvider).value;
      // Y su equivalencia: lo que hace posible avisar en un bloque R1, que es
      // percepción y no se traduce con una fórmula.
      final equiv = ref.read(equivalenciaZonasProvider).value;
      _audioController = SessionAudioController(
        audio: _audioCueService,
        rawBlocks: blocks,
        zonasFc: zonas?.zonas,
        equivalencia: equiv,
        onVibrar: () => HapticFeedback.mediumImpact(),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _gpsMapSub?.cancel();
    _precSub?.cancel();

    // SALIR SIN FINALIZAR DEJABA EL GPS GRABANDO PARA SIEMPRE.
    //
    // El dispose cancelaba los temporizadores de la pantalla pero nunca paraba el
    // GPS: si el atleta pulsaba la flecha atrás quedaban vivos el servicio en
    // primer plano con wakelock, el vigilante pidiendo posición cada 3 s y el
    // flujo a 2 Hz, hasta que cerrase la app. Batería drenada sin enterarse.
    // (Al FINALIZAR no se duplica: _onFinish ya lo paró y gpsActive es false.)
    try {
      if (ref.read(activeSessionProvider).gpsActive) {
        ref.read(activeSessionProvider.notifier).stopGPS();
      }
    } catch (_) {
      // Nunca romper el desmontaje de la pantalla por esto.
    }

    _audioCueService.stopSession();
    _audioCueService.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      ref.read(activeSessionProvider.notifier).tickSecond();
      if (_audioController != null) {
        final elapsed = ref.read(activeSessionProvider).elapsedSeconds;
        final distM   = ref.read(gpsServiceProvider).totalDistanceM.round();
        // La FC va también: cada bloque guarda su pulso medio y máximo.
        final hr      = ref.read(activeSessionProvider).currentHR;
        _audioController!.onTick(elapsed, distanceM: distM, hr: hr);
      }
    });
  }

  // Abre el scanner BLE. Puede llamarse antes o durante la sesión.
  Future<void> _openBleScan() async {
    final notifier = ref.read(activeSessionProvider.notifier);
    final device   = await context.push<BluetoothDevice?>(
      '/ble-scan/${widget.sessionId}',
    );
    if (device != null && mounted) {
      await notifier.connectBLE(device);
    }
  }

  Future<void> _onStart() async {
    if (_timer != null) return; // evitar doble inicio

    final notifier = ref.read(activeSessionProvider.notifier);
    final ble      = ref.read(bleServiceProvider);
    final gps      = ref.read(gpsServiceProvider);

    // 1. BLE — solo abrir scanner si no hay sensor ya conectado
    if (!ble.isConnected) {
      await _openBleScan();
    }

    // 2. GPS — pero solo si el DEPORTE lo pide.
    //    En fuerza no hay recorrido, y en una piscina el GPS solo graba ruido: pedir
    //    permiso de ubicación ahí es molestar al cliente para nada.
    final sport = Sport.fromApi(
        ref.read(activeSessionProvider).session?['sport'] as String?);
    gps.setSportType(sport.gpsSportType);

    var quiereGps = sport.usesGps;
    if (quiereGps && sport.askPoolOrOpenWater && mounted) {
      final donde = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('¿Dónde nadas?'),
          content: const Text(
              'En piscina el GPS no sirve (graba un garabato). En aguas abiertas '
              'sí registra tu recorrido.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'piscina'),
              child: const Text('Piscina'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, 'abiertas'),
              child: const Text('Aguas abiertas'),
            ),
          ],
        ),
      );
      quiereGps = donde == 'abiertas';
    }
    if (!quiereGps) {
      _sinGpsPorDeporte = true;   // no es un fallo: este deporte no lleva recorrido
    }

    // v7.2: si no hay GPS se AVISA y se pregunta — nunca arrancar mudos. El 18/07
    // el atleta corrio 81 min creyendo que se grababa el recorrido: 0 puntos.
    var gpsOk = quiereGps && await gps.requestPermission();
    if (!gpsOk && quiereGps && mounted) {
      final eleccion = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Sin ubicación'),
          content: const Text(
              'No puedo grabar tu recorrido: la ubicación del teléfono está '
              'desactivada o sin permiso.\n\nActívala y pulsa Reintentar para '
              'registrar kilómetros y ritmos.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'sin_gps'),
              child: const Text('Entrenar sin GPS'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, 'reintentar'),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
      if (eleccion == 'reintentar') {
        gpsOk = await gps.requestPermission();
      }
      if (!gpsOk) {
        _gpsOff = true;   // banner rojo: que se VEA que no hay recorrido
      }
    }
    if (gpsOk) {
      notifier.startGPS();
      _precSub?.cancel();
      _precSub = gps.accuracyStream.listen((m) {
        if (mounted) setState(() => _precisionM = m);
      });
      _gpsMapSub?.cancel();
      _gpsMapSub = gps.locationStream.listen((point) {
        if (!mounted) return;
        setState(() => _mapPoints.add(point));
        if (_mapReady) {
          try { _mapController.move(LatLng(point.lat, point.lng), 16); }
          catch (_) {}
        }
      }, onError: (Object e) {
        // El stream ha muerto (servicio apagado, permiso revocado…): avisar YA.
        if (!mounted) return;
        setState(() => _gpsOff = true);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('⚠️ Señal GPS perdida — el recorrido ha dejado de grabarse'),
          duration: Duration(seconds: 6),
        ));
      });
    }

    // 3. Marcar como activa e iniciar timer ANTES del API call.
    //    El FINALIZAR ya aparece aunque haya problema de red.
    notifier.markAsRunning();
    _initAudioController(); // por si aún no se había inicializado
    _startTimer();
    unawaited(_audioController?.onSessionStart());

    // 4. Sincronizar con backend (no bloqueante — la sesión ya corre localmente)
    try {
      await notifier.startSession(widget.sessionId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sesión activa. Sin sincronización con servidor.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Guarda una sesión de FUERZA: lo que de verdad hizo, serie a serie.
  ///
  /// Va a `actual_structure` (que ya existía, migración 040) porque es el sitio
  /// donde vive "lo real" frente a "lo planificado". De ahí saldrá el historial
  /// —"la última vez: 3×10 con 22 kg"— que es lo que permite progresar.
  ///
  /// La carga y la adherencia NO se mandan: las calcula el servidor desde el
  /// 11/08. Mandarlas desde aquí sería volver a dejar en el cliente un dato del
  /// que depende saber si el plan funcionó.
  Future<void> _guardarFuerza(List<Map<String, dynamic>> realizado) async {
    final id = widget.sessionId;
    final minutos = (ref.read(activeSessionProvider).elapsedSeconds / 60).round();
    try {
      await ref.read(apiClientProvider).completeSession(id, {
        'actualDurationMin': minutos > 0 ? minutos : null,
        'structure': ref.read(activeSessionProvider).session?['planned_structure']
                     ?? ref.read(activeSessionProvider).session?['structure'],
        'athleteFeedback': {'series_realizadas': realizado},
      });
      if (!mounted) return;
      context.go('/session/$id/complete');
    } catch (e) {
      if (!mounted) return;
      // El entrenamiento ya está hecho: lo que NO puede pasar es que se pierda
      // en silencio y el deportista crea que se ha guardado.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('No se pudo guardar. Revisa la conexión e inténtalo otra vez.'),
        backgroundColor: ref.read(activeSkinProvider).error));
    }
  }

  Future<void> _onFinish() async {
    final skin    = ref.read(activeSkinProvider);
    final elapsed = ref.read(activeSessionProvider).elapsedSeconds;
    final isShort = elapsed < 120; // menos de 2 minutos

    // Siempre pedir confirmación — aviso extra si la sesión fue muy corta
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: skin.backgroundCard,
        title: Text(
          isShort ? '⚠️  Sesión muy corta' : '¿Finalizar sesión?',
          style: TextStyle(color: skin.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: Text(
          isShort
              ? 'Solo llevas ${elapsed}s entrenando.\n¿Estás seguro de que quieres finalizar ya?'
              : 'Llevas ${_formatTime(elapsed)} entrenando.\n¿Confirmas el fin de la sesión?',
          style: TextStyle(color: skin.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Continuar entrenando', style: TextStyle(color: skin.accent)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: skin.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Finalizar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    _timer?.cancel();

    final notifier = ref.read(activeSessionProvider.notifier);
    final api      = ref.read(apiClientProvider);
    final session  = ref.read(activeSessionProvider);

    final track = notifier.stopGPS();
    if (track.points.isNotEmpty) {
      api.postGPSTrack(widget.sessionId, track.toBackendPayload())
          .catchError((e) { debugPrint('[GPS] Error upload: $e'); return <String, dynamic>{}; });
    }


    // CÓMO FUE CADA BLOQUE. El endpoint y la columna existían desde hace
    // tiempo; lo que faltaba era que alguien los llamara — postActualStructure
    // estaba escrito en el cliente y no lo invocaba nadie.
    final bloques = _audioController?.resultadosDeBloques ?? const [];
    if (bloques.isNotEmpty) {
      api.postActualStructure(widget.sessionId, bloques.map((b) => b.toJson()).toList())
          .catchError((e) { debugPrint('[BLOQUES] no se pudo guardar: $e'); return <String, dynamic>{}; });
    }
    if (session.bleConnected) await notifier.disconnectBLE();

    if (mounted) {
      context.pushReplacement('/session/${widget.sessionId}/complete');
    }
  }

  Future<void> _onRedo() async {
    final skin = ref.read(activeSkinProvider);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: skin.backgroundCard,
        title: Text('Sesión ya completada',
            style: TextStyle(color: skin.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text(
          'Esta sesión ya está registrada como completada por tu entrenador.\n\n'
          'Si la realizas de nuevo, los nuevos datos de entrenamiento reemplazarán a los anteriores.\n\n'
          '¿Quieres continuar?',
          style: TextStyle(color: skin.textSecondary, height: 1.55),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancelar', style: TextStyle(color: skin.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Realizar de nuevo'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _onStart();
  }

  String _formatTime(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Color _paceColor(double speedMps) {
    if (speedMps > 3.5) return const Color(0xFF22C55E); // rápido
    if (speedMps > 2.5) return const Color(0xFFEAB308); // medio
    return const Color(0xFFEF4444);                      // lento
  }

  Widget _buildLiveMap(SkinConfig skin) {
    final center = _mapPoints.isNotEmpty
        ? LatLng(_mapPoints.last.lat, _mapPoints.last.lng)
        : const LatLng(40.4168, -3.7038); // Madrid default

    final polylines = <Polyline>[];
    for (int i = 0; i < _mapPoints.length - 1; i++) {
      polylines.add(Polyline(
        points: [
          LatLng(_mapPoints[i].lat, _mapPoints[i].lng),
          LatLng(_mapPoints[i + 1].lat, _mapPoints[i + 1].lng),
        ],
        color: _paceColor(_mapPoints[i].speedMps),
        strokeWidth: 4,
      ));
    }

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 16,
            onMapReady: () {
              if (mounted) setState(() => _mapReady = true);
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.ritmooptimo.app',
            ),
            if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
            if (_mapPoints.isNotEmpty)
              MarkerLayer(
                markers: [
                  Marker(
                    point: center,
                    width: 20,
                    height: 20,
                    child: Container(
                      decoration: BoxDecoration(
                        color: skin.accent,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: skin.accent.withValues(alpha: 0.5),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
        if (_mapPoints.isEmpty)
          Positioned(
            top: 8, left: 0, right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Esperando señal GPS...',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final skin    = ref.watch(activeSkinProvider);
    final session = ref.watch(activeSessionProvider);

    final sessionStatus  = session.session?['status'] as String? ?? '';
    final isCompleted    = !_loadingSession && sessionStatus == 'completed' && !session.isRunning;
    final isPreStart     = !_loadingSession && !session.isRunning && !isCompleted;

    // ── FUERZA: otra pantalla, porque es otro entrenamiento ──────────────
    //
    // Esta pantalla está construida sobre GPS, ritmo y frecuencia cardiaca. Para
    // una sentadilla nada de eso significa nada: lo que hace falta es saber qué
    // ejercicio toca, por qué serie vas y cuánto queda de descanso.
    //
    // ⚠️ La decisión NO se toma por `session_type`, sino por si la sesión TRAE
    // ejercicios. Es la diferencia entre preguntar por la etiqueta y preguntar
    // por el contenido: una sesión de fuerza antigua (de las que eran un párrafo)
    // sigue abriendo la pantalla de siempre, y una de otro tipo que traiga
    // ejercicios se guía bien igualmente.
    // ⚠️ EL CAMPO SE LLAMA `planned_structure`, NO `structure`.
    //
    // El endpoint devuelve `structure AS planned_structure`, y esta condición
    // leía `structure` — que NO EXISTE en la respuesta. Resultado:
    // `desdeEstructura(null)` daba vacío, la pantalla de fuerza NO SE ABRÍA
    // NUNCA, y el deportista veía la pantalla de carrera con tres bloques
    // («Calentamiento, Fuerza general, Vuelta a la calma») en vez de sus
    // ejercicios.
    //
    // Toda esta pantalla —los pasos aplanados de un circuito, el descanso entre
    // series, el RIR al acabar— estaba escrita y no se ha ejecutado jamás. Es la
    // tercera cosa así hoy: la guía de repeticiones de las series y el aviso de
    // zona tenían el mismo problema.
    final estructuraFuerza = session.session?['planned_structure']
        ?? session.session?['structure'];

    // ⚠️ SOLO CUANDO YA ESTÁ CORRIENDO. Sin `session.isRunning`, esta pantalla
    // se abría EN CUANTO CARGABA la sesión: la de siempre —la que enseña lo que
    // se va a hacer y deja elegir el pulsómetro— aparecía un instante y saltaba
    // sola a la guía de ejercicios sin que nadie hubiera pulsado COMENZAR.
    //
    // El orden importa: primero se ve lo que toca y se decide si se pone la
    // banda; solo después se entra a ejecutar.
    if (!_loadingSession && session.session != null &&
        !isCompleted && session.isRunning &&
        BloqueFuerza.desdeEstructura(estructuraFuerza).isNotEmpty) {
      return FuerzaSessionScreen(
        session: { ...session.session!, 'structure': estructuraFuerza },
        onFinish: (realizado) => _guardarFuerza(realizado),
      );
    }

    return Scaffold(
      backgroundColor: skin.background,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: skin.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          isCompleted        ? 'COMPLETADA'
              : session.isRunning ? 'EN CURSO'
              : 'SESIÓN',
          style: TextStyle(
              color: isCompleted ? skin.success : skin.textPrimary,
              letterSpacing: 2,
              fontSize: 14),
        ),
        backgroundColor: skin.backgroundSecondary,
        actions: [
          // Elegir la voz que guía la sesión. Antes de empezar, que es cuando
          // tiene sentido probarla: con la sesión en marcha estorbaría.
          if (!session.isRunning && !isCompleted)
            IconButton(
              icon: Icon(Icons.record_voice_over_outlined, color: skin.textMuted),
              tooltip: 'Voz de la sesión',
              onPressed: () => VoicePickerSheet.mostrar(context, _audioCueService),
            ),
          if (session.isRunning)
            TextButton(
              onPressed: _onFinish,
              child: Text('FINALIZAR',
                  style: TextStyle(
                      color: skin.error, fontWeight: FontWeight.w700, letterSpacing: 1)),
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Header: timer (en curso) o resumen (completada) ──
          _SessionHeader(
            skin: skin,
            session: session,
            elapsed: _formatTime(session.elapsedSeconds),
            isCompleted: isCompleted,
            sport: Sport.fromApi(session.session?['sport'] as String?),
          ),

          // ── Banner "Completada" con datos reales ──────────
          if (isCompleted)
            _CompletedSummaryBanner(skin: skin, sessionData: session.session!),

          // ── Estado sensores — solo cuando no está completada ─
          if (!isCompleted) ...[
            _SensorStatusRow(skin: skin, session: session, onConnectBle: _openBleScan),
            const SizedBox(height: 8),
            // Sin GPS no hay mapa: en fuerza o en piscina ocupaba 230 px en blanco.
            if (session.isRunning && !_sinGpsPorDeporte) ...[
              const Divider(height: 1, thickness: 0.5),
              SizedBox(height: 230, child: _buildLiveMap(skin)),
            ],
            // ── AGS: progreso de bloque en curso ──────────
            if (session.isRunning && _audioController != null) ...[
              BlockProgressWidget(
                uiState: _audioController!.getUIState(session.elapsedSeconds),
                skin: skin,
                onSkip: () => setState(() => _audioController?.requestSkip()),
              ),
              if (_audioController!.currentBlock?.isInterval == true)
                IntervalRepWidget(
                  smoothedPaceSecKm: ref.read(gpsServiceProvider).smoothedPaceSecKm,
                  targetPace: _audioController!.currentBlock?.targetPace,
                  skin: skin,
                ),
            ],
          ],

          // ── Estado del GPS: visible SIEMPRE (v7.2) ───────
          if (_gpsOff)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF450A0A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFEF4444)),
              ),
              child: const Text('🛰️ SIN GPS — el recorrido NO se está grabando',
                  style: TextStyle(color: Color(0xFFFCA5A5), fontSize: 13,
                      fontWeight: FontWeight.w700)),
            )
          else if (_timer != null && _mapPoints.isEmpty && !_sinGpsPorDeporte)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF3A2E10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFF59E0B)),
              ),
              // Decir la precision REAL: "Buscando senal" a secas escondia que el
              // GPS iba bien y era la app la que descartaba los puntos.
              child: Text(
                  _precisionM == null
                      ? '🛰️ Buscando señal GPS… (sal a cielo abierto)'
                      : '🛰️ Señal débil: ±${_precisionM!.round()} m — buscando precisión…',
                  style: const TextStyle(color: Color(0xFFFCD34D), fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ),

          // ── Bloques del plan ─────────────────────────────
          Expanded(
            child: _SessionBlocks(
              planned: session.session?['planned_structure'] as List<dynamic>? ?? [],
              elapsed: session.elapsedSeconds,
              skin: skin,
              esLibre: session.session?['is_free_session'] == true,
            ),
          ),

          // ── Área inferior: botón según estado ────────────
          if (_loadingSession)
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: null,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2,
                              color: skin.textMuted)),
                      const SizedBox(width: 12),
                      Text('Cargando sesión...',
                          style: TextStyle(color: skin.textMuted)),
                    ],
                  ),
                ),
              ),
            )
          else if (isCompleted)
            _CompletedFooter(skin: skin, onRedo: _onRedo)
          else if (session.isRunning)
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: skin.error, foregroundColor: Colors.white),
                  onPressed: _onFinish,
                  child: const Text('FINALIZAR SESIÓN',
                      style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 2)),
                ),
              ),
            )
          // En un día de descanso no se ofrece empezar. Inicio ya escondía su
          // botón para 'rest', pero desde el Plan se llegaba aquí y salía
          // "COMENZAR" igual: el mismo día decía descanso en una pantalla y te
          // invitaba a entrenar en la otra.
          else if (sessionStatus == 'rest')
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  Icon(Icons.hotel_outlined, color: skin.textMuted, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Hoy toca descansar. El descanso también entrena.',
                      style: TextStyle(color: skin.textMuted, fontSize: 13),
                    ),
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: isPreStart ? _onStart : null,
                  child: const Text('COMENZAR',
                      style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 2)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Session Header (timer + FC + ritmo) ─────────────────────────

class _SessionHeader extends StatelessWidget {
  final SkinConfig skin;
  final ActiveSessionState session;
  final String elapsed;
  final bool isCompleted;
  final Sport sport;
  const _SessionHeader(
      {required this.skin, required this.session, required this.elapsed,
       this.isCompleted = false, this.sport = Sport.running});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      color: skin.backgroundSecondary,
      child: Column(
        children: [
          if (isCompleted)
            Icon(Icons.check_circle_outline, size: 56, color: skin.success)
          else
            Text(
              elapsed,
              style: TextStyle(
                fontFamily: skin.fontFamilyMono,
                fontSize: 56,
                fontWeight: FontWeight.w700,
                color: session.isRunning ? skin.accent : skin.textMuted,
                letterSpacing: 4,
              ),
            ),
          const SizedBox(height: 16),
          // Cada deporte, sus métricas: min/km en carrera, km/h en bici, /100m
          // nadando, y en fuerza ni ritmo ni distancia — pulso y tiempo.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _DataBadge(
                label: 'FC',
                value: session.currentHR != null
                    ? '${session.currentHR}'
                    : '--',
                unit: 'bpm',
                icon: Icons.favorite,
                color: skin.error,
                skin: skin,
              ),
              if (sport.speedMode != SpeedMode.none) ...[
                const SizedBox(width: 32),
                _DataBadge(
                  label: sport.speedLabel,
                  value: sport.formatSpeed(session.currentPace),
                  unit: sport.speedUnit,
                  icon: Icons.speed,
                  color: skin.accent,
                  skin: skin,
                ),
              ],
              if (sport.hasDistance) ...[
                const SizedBox(width: 32),
                _DataBadge(
                  label: 'DIST',
                  value: sport.formatDistance(session.totalDistanceM),
                  unit: sport.distanceUnit,
                  icon: Icons.route,
                  color: skin.accentSecondary,
                  skin: skin,
                ),
              ],
              // En fuerza el hueco de ritmo/distancia lo ocupa lo que sí importa:
              // cómo ha ido el pulso durante la sesión.
              if (sport == Sport.fuerza) ...[
                const SizedBox(width: 32),
                _DataBadge(
                  label: 'MEDIA',
                  value: session.hrAvg != null ? '${session.hrAvg}' : '--',
                  unit: 'bpm',
                  icon: Icons.monitor_heart_outlined,
                  color: skin.accent,
                  skin: skin,
                ),
                const SizedBox(width: 32),
                _DataBadge(
                  label: 'MÁX',
                  value: session.hrMax != null ? '${session.hrMax}' : '--',
                  unit: 'bpm',
                  icon: Icons.arrow_upward,
                  color: skin.accentSecondary,
                  skin: skin,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

}

// ── Sensor status row (BLE + GPS) — siempre visible ─────────────

class _SensorStatusRow extends StatelessWidget {
  final dynamic skin;
  final ActiveSessionState session;
  final VoidCallback onConnectBle;
  const _SensorStatusRow(
      {required this.skin, required this.session, required this.onConnectBle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          Expanded(child: _BleCard(skin: skin, session: session, onConnect: onConnectBle)),
          const SizedBox(width: 8),
          Expanded(child: _GpsCard(skin: skin, session: session)),
        ],
      ),
    );
  }
}

class _BleCard extends StatelessWidget {
  final dynamic skin;
  final ActiveSessionState session;
  final VoidCallback onConnect;
  const _BleCard(
      {required this.skin, required this.session, required this.onConnect});

  @override
  Widget build(BuildContext context) {
    final connected = session.bleConnected;
    final name      = session.bleDeviceName ?? 'Sensor FC';
    final hr        = session.currentHR;

    return GestureDetector(
      onTap: connected ? null : onConnect,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: connected
              ? skin.success.withValues(alpha: 0.1)
              : skin.backgroundCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: connected ? skin.success : skin.border,
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            Icon(
              connected
                  ? Icons.bluetooth_connected
                  : Icons.bluetooth_searching,
              size: 18,
              color: connected ? skin.success : skin.textMuted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    connected ? name : 'Sin sensor FC',
                    style: TextStyle(
                      color: connected ? skin.success : skin.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (connected)
                    Text(
                      hr != null ? '$hr bpm' : 'Ponte la banda en el pecho',
                      style: TextStyle(
                        color: hr != null ? skin.error : skin.textMuted,
                        fontSize: hr != null ? 13 : 10,
                        fontWeight: hr != null ? FontWeight.w700 : FontWeight.normal,
                        fontFamily: hr != null ? skin.fontFamilyMono : null,
                      ),
                    )
                  else
                    Text(
                      'Toca para conectar',
                      style: TextStyle(color: skin.accent, fontSize: 11),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GpsCard extends StatelessWidget {
  final dynamic skin;
  final ActiveSessionState session;
  const _GpsCard({required this.skin, required this.session});

  @override
  Widget build(BuildContext context) {
    final active = session.gpsActive;
    final dist   = session.totalDistanceM;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: active ? skin.accent.withValues(alpha: 0.08) : skin.backgroundCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: active ? skin.accent : skin.border,
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Icon(
            active ? Icons.gps_fixed : Icons.gps_off,
            size: 18,
            color: active ? skin.accent : skin.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GPS',
                  style: TextStyle(
                    color: active ? skin.accent : skin.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  active
                      ? (dist > 0
                          ? '${(dist / 1000).toStringAsFixed(2)} km'
                          : 'Activo')
                      : 'Al comenzar',
                  style: TextStyle(
                    color: active ? skin.accentSecondary : skin.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFamily: dist > 0 ? skin.fontFamilyMono : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bloques del plan ────────────────────────────────────────────

class _SessionBlocks extends StatelessWidget {
  final List<dynamic> planned;
  final int elapsed;
  final dynamic skin;
  final bool esLibre;
  const _SessionBlocks(
      {required this.planned, required this.elapsed, required this.skin,
       this.esLibre = false});

  static num _blockDurMin(Map<String, dynamic> b) {
    final v = b['min'] ?? b['durationMin'] ?? b['duracion_min'] ?? b['duration_min'] ?? b['dur_min'] ?? 0;
    if (v is num) return v;
    return num.tryParse(v.toString()) ?? 0;
  }

  int _activeIndex() {
    int cumSecs = 0;
    for (int i = 0; i < planned.length; i++) {
      final block  = planned[i] as Map<String, dynamic>? ?? {};
      final durMin = _blockDurMin(block);
      cumSecs += (durMin.toDouble() * 60).round();
      if (elapsed < cumSecs) return i;
    }
    return planned.isEmpty ? -1 : planned.length - 1;
  }

  @override
  Widget build(BuildContext context) {
    if (planned.isEmpty) {
      return Center(
        child: Text(
          // En una sesión libre no faltan bloques: es que no los lleva.
          esLibre
              ? 'Entrenamiento libre — tú marcas el ritmo.'
              : 'No hay bloques definidos para esta sesión.',
          style: TextStyle(color: skin.textMuted, fontSize: 13),
          textAlign: TextAlign.center,
        ),
      );
    }

    final activeIdx = _activeIndex();

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: planned.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _BlockCard(
        block: planned[i] as Map<String, dynamic>? ?? {},
        isActive: i == activeIdx,
        skin: skin,
        index: i,
      ),
    );
  }
}

class _BlockCard extends StatelessWidget {
  final Map<String, dynamic> block;
  final bool isActive;
  final dynamic skin;
  final int index;
  const _BlockCard(
      {required this.block,
      required this.isActive,
      required this.skin,
      required this.index});

  String _blockLabel() {
    final tipo = (block['block'] ?? block['blockType'] ?? block['tipo'] ?? block['type'] ?? block['nombre'] ?? '').toString();
    if (tipo.isEmpty) return 'Bloque ${index + 1}';
    return tipo[0].toUpperCase() + tipo.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final durMin = _SessionBlocks._blockDurMin(block);
    final zonaFC = block['zone'] ?? block['zona_fc'] ?? block['hr_zone'] ?? block['zona'];
    final ritmo  = block['ritmo_objetivo'] ?? block['target_pace'] ?? block['pace'];
    final desc   = block['descripcion'] ?? block['description'] ?? block['desc'] ?? '';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: isActive ? skin.accent.withValues(alpha: 0.12) : skin.backgroundCard,
        borderRadius: BorderRadius.circular(skin.cardRadius),
        border: Border.all(
          color: isActive ? skin.accent : skin.border,
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // Indicador bloque activo
            Container(
              width: 4,
              height: 48,
              decoration: BoxDecoration(
                color: isActive ? skin.accent : skin.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        _blockLabel(),
                        style: TextStyle(
                          color: isActive ? skin.accent : skin.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${durMin.toInt()} min',
                        style: TextStyle(
                          fontFamily: skin.fontFamilyMono,
                          color: skin.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      desc.toString(),
                      style: TextStyle(
                          color: skin.textSecondary, fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  // Lo que se va a hacer de verdad, no solo cuánto dura.
                  if (resumenSerieDe(block) != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      resumenSerieDe(block)!,
                      style: TextStyle(
                          color: isActive ? skin.accent : skin.textPrimary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                  if (lineasEjercicios(block).isNotEmpty) ...[
                    const SizedBox(height: 5),
                    // ⚠️ En su PROPIA columna y con ellipsis: con la letra al
                    // 180 % una fila que no cabe recorta sin avisar, y aquí lo
                    // que se pierde es qué ejercicio toca.
                    ...(lineasEjercicios(block).map((linea) => Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '· $linea',
                            style: TextStyle(
                                color: skin.textSecondary, fontSize: 12, height: 1.3),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ))),
                    if (resumenRondas(block) != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        resumenRondas(block)!,
                        style: TextStyle(
                            color: isActive ? skin.accent : skin.textMuted,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ],
                  if (zonaFC != null || ritmo != null) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (zonaFC != null)
                          _Tag(
                              // ⚠️ CON SU ESCALA. Sin esto, un bloque en R2
                              // se pintaba «Z2 FC» — otra escala y treinta
                              // pulsaciones menos que lo que pide el plan.
                              label: etiquetaZonaFc(zonaFC,
                                  escala: block['zone_escala'] as String?)!,
                              color: skin.error,
                              skin: skin),
                        if (ritmo != null)
                          _Tag(
                              label: ritmo.toString(),
                              color: skin.accent,
                              skin: skin),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color color;
  final dynamic skin;
  const _Tag({required this.label, required this.color, required this.skin});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label,
            style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5)),
      );
}

// ── Banner resumen cuando la sesión está completada ──────────────

class _CompletedSummaryBanner extends StatelessWidget {
  final dynamic skin;
  final Map<String, dynamic> sessionData;
  const _CompletedSummaryBanner({required this.skin, required this.sessionData});

  @override
  Widget build(BuildContext context) {
    final actualMin  = (sessionData['actual_duration_min'] as num?)?.toInt();
    final actualDistM= (sessionData['actual_distance_m']   as num?)?.toDouble();
    final actualHr   = (sessionData['actual_hr_avg_bpm']   as num?)?.toInt();
    final completedAt= sessionData['completed_at'] as String?;

    String? completedLabel;
    if (completedAt != null) {
      try {
        final dt = DateTime.parse(completedAt).toLocal();
        completedLabel = '${dt.day.toString().padLeft(2,'0')}/${dt.month.toString().padLeft(2,'0')} '
            '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
      } catch (_) {}
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: skin.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(skin.cardRadius),
        border: Border.all(color: skin.success.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.check_circle, color: skin.success, size: 16),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Sesión completada${completedLabel != null ? " · $completedLabel" : ""}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: skin.success, fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
          ]),
          if (actualMin != null || actualDistM != null || actualHr != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (actualMin != null)
                  _SummaryChip(label: '$actualMin min', icon: Icons.timer_outlined, skin: skin),
                if (actualDistM != null && actualDistM > 0)
                  _SummaryChip(
                      label: '${(actualDistM / 1000).toStringAsFixed(2)} km',
                      icon: Icons.route_outlined, skin: skin),
                if (actualHr != null)
                  _SummaryChip(label: '$actualHr bpm', icon: Icons.favorite_outline, skin: skin),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final dynamic skin;
  const _SummaryChip({required this.label, required this.icon, required this.skin});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 16),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: skin.textMuted),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(color: skin.textSecondary, fontSize: 12,
          fontFamily: skin.fontFamilyMono)),
    ]),
  );
}

// ── Pie de página cuando la sesión está completada ───────────────

class _CompletedFooter extends StatelessWidget {
  final dynamic skin;
  final VoidCallback onRedo;
  const _CompletedFooter({required this.skin, required this.onRedo});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      // Indicador visual "Completada"
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: skin.success.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(skin.cardRadius),
          border: Border.all(color: skin.success.withValues(alpha: 0.3)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.check_circle, color: skin.success, size: 20),
          const SizedBox(width: 10),
          Text('Completada — buen trabajo',
              style: TextStyle(color: skin.success, fontWeight: FontWeight.w600, fontSize: 14)),
        ]),
      ),
      const SizedBox(height: 10),
      // Botón "realizar de nuevo" discreto
      SizedBox(
        width: double.infinity,
        height: 44,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: skin.textMuted,
            side: BorderSide(color: skin.border),
          ),
          icon: Icon(Icons.replay, size: 16, color: skin.textMuted),
          label: Text('Realizar de nuevo',
              style: TextStyle(color: skin.textMuted, letterSpacing: 0.5)),
          onPressed: onRedo,
        ),
      ),
    ]),
  );
}

class _DataBadge extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final Color color;
  final SkinConfig skin;
  const _DataBadge(
      {required this.label,
      required this.value,
      required this.unit,
      required this.icon,
      required this.color,
      required this.skin});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(height: 4),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: value,
                style: TextStyle(
                  fontFamily: skin.fontFamilyMono,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              TextSpan(
                text: unit,
                style: TextStyle(
                  fontSize: 11,
                  color: skin.textMuted,
                ),
              ),
            ],
          ),
        ),
        Text(label,
            style: TextStyle(
                color: skin.textMuted, fontSize: 10, letterSpacing: 1.5)),
      ],
    );
  }
}
