import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/api_client.dart';
import '../../core/gps/gps_service.dart';
import '../../providers/skin_provider.dart';
import '../../models/sport.dart';
import '../../config/skins/skin_config.dart';
import '../../widgets/route_map_widget.dart';

// pg devuelve las columnas `numeric` como STRING ("0.649"); estos parsers
// aceptan num O String para que un `as num` no reviente el resumen. Bug real:
// total_distance_km/elevation/training_load son numeric → llegaban como texto
// y la pantalla de una sesión completada con GPS moría con "Error al cargar".
double? _pd(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

int? _pi(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  return num.tryParse(v.toString())?.toInt();
}

// ── Provider ─────────────────────────────────────────────────────
final _summaryProvider = FutureProvider.family<_SummaryData, String>((ref, id) async {
  final api     = ref.read(apiClientProvider);
  final session = await api.getSession(id);
  final gpsRaw  = await api.getGPSTrack(id);

  List<GpsPoint> gpsPoints = [];
  double? distKm, paceSecKm;
  double? elevGainM, elevLossM;
  List<_PaceSplit>   paceSplits    = [];
  Map<String, int>?  serverHrZones;
  double? trainingLoad;
  int?    fastestKmPace;
  int?    cadenceAvg;
  String? sportType;
  // CÓMO FUE CADA BLOQUE. Lo guarda la app al terminar (actual_structure).
  // "para que el deportista sepa cómo ha realizado el bloque concreto" — David.
  List<Map<String, dynamic>> bloques = [];
  final rawBloques = session['actual_structure'];
  if (rawBloques is List) {
    bloques = rawBloques.whereType<Map>().map((b) => Map<String, dynamic>.from(b)).toList();
  }

  if (gpsRaw != null) {
    distKm    = _pd(gpsRaw['total_distance_km']);
    paceSecKm = _pd(gpsRaw['avg_pace_sec_km']);
    elevGainM = _pd(gpsRaw['elevation_gain_m']);
    elevLossM = _pd(gpsRaw['elevation_loss_m']);
    trainingLoad   = _pd(gpsRaw['training_load']);
    fastestKmPace  = _pi(gpsRaw['fastest_km_pace_sec']);
    cadenceAvg     = _pi(gpsRaw['cadence_avg_rpm']);
    sportType      = gpsRaw['sport_type'] as String?;

    // Pace splits (server-computed)
    final rawSplits = gpsRaw['pace_splits'] as List? ?? [];
    paceSplits = rawSplits.map((s) {
      final m = s as Map;
      return _PaceSplit(
        km:        _pi(m['km']) ?? 0,
        paceSec:   _pi(m['pace_sec']) ?? 0,
        hrAvg:     _pi(m['hr_avg']) ?? 0,
        elevationM: _pi(m['elevation_m']),
      );
    }).where((s) => s.paceSec > 0).toList();

    // ZONAS DE FC — las del entrenador si vienen, si no las genéricas.
    //
    // El servidor manda ahora las seis de Raúl (R0…R3+), calculadas por FC de
    // RESERVA. Las z1-z5 siguen llegando porque las salidas guardadas antes del
    // 07/08 solo tienen esas: si mirásemos únicamente las nuevas, el resumen de
    // una sesión antigua saldría con todas las barras a cero.
    final rawZones = gpsRaw['hr_zones_sec'] as Map?;
    if (rawZones != null && rawZones.isNotEmpty) {
      const rKeys = ['R0', 'R1', 'R1+', 'R2', 'R3', 'R3+'];
      final tieneR = rKeys.any((k) => (_pi(rawZones[k]) ?? 0) > 0);
      serverHrZones = tieneR
          ? { for (final k in rKeys) k: _pi(rawZones[k]) ?? 0 }
          : {
              'Z1': _pi(rawZones['z1']) ?? 0,
              'Z2': _pi(rawZones['z2']) ?? 0,
              'Z3': _pi(rawZones['z3']) ?? 0,
              'Z4': _pi(rawZones['z4']) ?? 0,
              'Z5': _pi(rawZones['z5']) ?? 0,
            };
    }

    // GPS points for map
    final pts = gpsRaw['track_points'] as List? ?? [];
    gpsPoints = pts.map((p) {
      final m = p as Map;
      return GpsPoint(
        lat:      _pd(m['lat']) ?? 0,
        lng:      _pd(m['lng']) ?? 0,
        alt:      _pd(m['alt']) ?? 0,
        speedMps: _pd(m['speed_mps']) ?? 0,
        accuracy: _pd(m['accuracy']) ?? 0,
        timestamp: m['timestamp'] as String? ?? '',
        hr:       _pi(m['hr']),
        cadence:  _pi(m['cadence']),
        powerW:   _pi(m['power_w']),
      );
    }).toList();
  }

  return _SummaryData(
    session:      session,
    gpsPoints:    gpsPoints,
    distKm:       distKm,
    paceSecKm:    paceSecKm,
    elevGainM:    elevGainM,
    elevLossM:    elevLossM,
    paceSplits:   paceSplits,
    serverHrZones: serverHrZones,
    trainingLoad:  trainingLoad,
    fastestKmPace: fastestKmPace,
    cadenceAvg:    cadenceAvg,
    sportType:     sportType,
    bloques:       bloques,
  );
});

class _PaceSplit {
  final int km;
  final int paceSec;
  final int hrAvg;
  final int? elevationM;
  const _PaceSplit({required this.km, required this.paceSec,
      required this.hrAvg, this.elevationM});
}

class _SummaryData {
  final Map<String, dynamic> session;
  final List<GpsPoint>       gpsPoints;
  final double?              distKm;
  final double?              paceSecKm;
  final double?              elevGainM;
  final double?              elevLossM;
  final List<_PaceSplit>     paceSplits;
  final Map<String, int>?    serverHrZones;
  final double?              trainingLoad;
  final int?                 fastestKmPace;
  final int?                 cadenceAvg;
  final String?              sportType;
  final List<Map<String, dynamic>> bloques;

  const _SummaryData({
    required this.session,
    required this.gpsPoints,
    this.distKm,
    this.paceSecKm,
    this.elevGainM,
    this.elevLossM,
    this.paceSplits = const [],
    this.serverHrZones,
    this.trainingLoad,
    this.fastestKmPace,
    this.cadenceAvg,
    this.sportType,
    this.bloques = const [],
  });
}

// ── Pantalla principal ───────────────────────────────────────────
class SessionSummaryScreen extends ConsumerWidget {
  final String sessionId;
  const SessionSummaryScreen({super.key, required this.sessionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin  = ref.watch(activeSkinProvider);
    final async = ref.watch(_summaryProvider(sessionId));

    return Scaffold(
      backgroundColor: skin.background,
      body: async.when(
        loading: () => Center(child: CircularProgressIndicator(color: skin.accent)),
        error: (e, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.error_outline, color: skin.error, size: 40),
            const SizedBox(height: 12),
            Text('Error al cargar sesión', style: TextStyle(color: skin.textMuted)),
            const SizedBox(height: 16),
            TextButton(onPressed: () => context.go('/'), child: const Text('Volver')),
          ]),
        ),
        data: (data) => _SummaryBody(skin: skin, data: data, sessionId: sessionId),
      ),
    );
  }
}

// ── Cuerpo del resumen ───────────────────────────────────────────
class _SummaryBody extends StatelessWidget {
  final SkinConfig skin;
  final _SummaryData data;
  final String sessionId;

  const _SummaryBody({required this.skin, required this.data, required this.sessionId});

  // ── Helpers ──────────────────────────────────────────────────
  int    get _durMin  => _pi(data.session['actual_duration_min']) ?? 0;
  int    get _hrAvg   => _pi(data.session['actual_hr_avg_bpm'])   ?? 0;
  int    get _hrMax   => _pi(data.session['actual_hr_max_bpm'])   ?? 0;
  int    get _rpe     => _pi(data.session['actual_rpe'])          ?? 0;
  int    get _planMin => _pi(data.session['planned_duration_min']) ?? 0;
  int    get _planDistM => _pi(data.session['planned_distance_m']) ?? 0;

  double get _distKm {
    if (data.distKm != null && data.distKm! > 0) return data.distKm!;
    final m = _pd(data.session['actual_distance_m']) ?? 0;
    return m / 1000;
  }

  int get _estCal {
    if (_durMin <= 0) return 0;
    final intensity = _hrAvg > 0 ? (_hrAvg / 150.0).clamp(0.5, 1.8) : 1.0;
    return (_durMin * 8.5 * intensity).round();
  }

  Sport get _sport => Sport.fromApi(
      (data.session['sport'] as String?) ?? data.sportType);

  String _fmtPace(int secKm) {
    if (secKm <= 0) return '--';
    final min = secKm ~/ 60;
    final sec = secKm % 60;
    return "$min'${sec.toString().padLeft(2, '0')}\"";
  }

  String get _paceStr {
    final secKm = (data.paceSecKm != null && data.paceSecKm! > 0)
        ? data.paceSecKm!
        : (_distKm > 0 && _durMin > 0) ? (_durMin * 60) / _distKm : 0.0;
    if (secKm <= 0) return '--';
    // En carrera 4'30"/km; en bici 26,7 km/h; nadando 1'52"/100m. El mismo dato
    // en las unidades que el deportista entiende.
    if (_sport.speedMode == SpeedMode.pacePerKm) return _fmtPace(secKm.round());
    return _sport.formatSpeed(secKm);
  }

  String get _dateStr {
    final raw = data.session['scheduled_date'] as String? ?? '';
    final dp  = raw.length >= 10 ? raw.substring(0, 10) : raw;
    final pts = dp.split('-');
    if (pts.length < 3) return raw;
    const months = ['', 'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
        'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
    final m = int.tryParse(pts[1]) ?? 0;
    return '${pts[2]} de ${months[m]} ${pts[0]}';
  }

  String get _completedTime {
    final raw = data.session['completed_at'] as String?;
    if (raw == null) return '';
    try {
      final dt = DateTime.parse(raw).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) { return ''; }
  }

  // ZONAS DE FC: SOLO las que calcula el servidor.
  //
  // Antes, si el servidor no las mandaba, se calculaban aquí usando como FC
  // máxima teórica la FC MÁXIMA DE ESTA MISMA SESIÓN. En un rodaje suave con
  // máxima de 140 eso ponía todos los puntos al 90-100 % → el atleta leía
  // "50 minutos en Z5" después de un trote regenerativo. Y la estimación desde
  // la FC media era directamente inventada.
  //
  // El servidor sí conoce la FC máxima real del perfil (178 en el caso de David)
  // y ahora también decide si la FC de la sesión es creíble. Si no hay zonas del
  // servidor, no se pintan: mejor no decir nada que decir algo falso.
  Map<String, int> get _zoneSeconds {
    final z = data.serverHrZones;
    if (z == null || z.isEmpty) return {};
    return z.values.fold(0, (a, b) => a + b) > 0 ? z : {};
  }

  bool get _isMissed => data.session['status'] == 'missed';

  String _motivationalMsg() {
    // Una sesión perdida no se celebra. Tampoco se riñe: se pasa página, que es
    // lo que haría un entrenador de verdad.
    if (_isMissed) {
      return 'Este día no pudo ser, y no pasa nada. Lo que cuenta es la próxima '
             'sesión: retomarla es lo que sostiene el progreso.';
    }
    if (_rpe >= 9) return '¡Esfuerzo máximo! Esa determinación marca la diferencia.';
    if (_rpe >= 7) return '¡Gran trabajo! Sesión muy exigente bien ejecutada.';
    if (data.trainingLoad != null && data.trainingLoad! > 80) return '¡Carga alta! Tu cuerpo está absorbiendo el estímulo. Descansa bien.';
    if (_distKm > 20) return '¡Distancia impresionante! Tu resistencia sigue creciendo.';
    if (_distKm > 10) return '¡Sólida sesión! Esos kilómetros suman a tu forma física.';
    if (_durMin > 90) return '¡Más de hora y media entrenando! Eso es dedicación real.';
    if (_rpe <= 3) return 'Sesión de recuperación perfecta. Tu cuerpo lo agradece.';
    return '¡Sesión completada! Cada entrenamiento te acerca a tu mejor versión.';
  }

  @override
  Widget build(BuildContext context) {
    final feedback   = data.session['athlete_feedback'] as Map? ?? {};
    final notes      = feedback['notes']         as String?;
    final energy     = _pi(feedback['energy_level']);
    final zones      = _zoneSeconds;
    final hasGPS     = data.gpsPoints.length >= 2;
    final hasSplits  = data.paceSplits.length >= 2;
    final hasElev    = (data.elevGainM ?? 0) > 0 || (data.elevLossM ?? 0) > 0;
    final hasMetrics = _durMin > 0 || _hrAvg > 0 || _distKm > 0;

    return CustomScrollView(
      slivers: [

        // ── Hero banner ───────────────────────────────────────
        SliverToBoxAdapter(child: _HeroBanner(
          skin:    skin,
          title:   data.session['title']        as String? ?? 'Sesión',
          type:    data.session['session_type'] as String? ?? '',
          dateStr: _dateStr,
          timeStr: _completedTime,
          sport:   data.sportType,
          missed:  _isMissed,
        )),

        // ── Métricas principales ──────────────────────────────
        if (hasMetrics) SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: _MetricsGrid(
            skin:         skin,
            sport:        _sport,
            durMin:       _durMin,
            distKm:       _distKm,
            hrAvg:        _hrAvg,
            hrMax:        _hrMax,
            pace:         _paceStr,
            estCal:       _estCal,
            elevGainM:    data.elevGainM,
            cadenceAvg:   data.cadenceAvg,
            trainingLoad: data.trainingLoad,
          ),
        )),

        // ── Gráfico de ritmo por km ───────────────────────────
        if (hasSplits) ...[
          SliverToBoxAdapter(child: _SectionHeader(
              _sport.speedMode == SpeedMode.speedKmh
                  ? 'Velocidad por kilómetro'
                  : 'Ritmo por kilómetro', skin, icon: Icons.show_chart)),
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _PaceChart(
              skin:   skin,
              splits: data.paceSplits,
              hrMax:  _hrMax > 0 ? _hrMax : 190,
            ),
          )),
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: _SplitsTable(skin: skin, splits: data.paceSplits, fmtPace: _fmtPace),
          )),
        ],

        // ── Cómo fue cada bloque ──────────────────────────────
        // Pedido por David: cada bloque con SUS kilómetros y su ritmo, además
        // del total de la sesión. Solo aparece si la sesión la guió la app.
        if (data.bloques.isNotEmpty) ...[
          SliverToBoxAdapter(child: _SectionHeader('Por bloques', skin, icon: Icons.view_agenda_outlined)),
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: _TablaBloques(skin: skin, bloques: data.bloques, fmtPace: _fmtPace),
          )),
        ],

        // ── Mapa de ruta ──────────────────────────────────────
        if (hasGPS) ...[
          SliverToBoxAdapter(child: _SectionHeader('Recorrido', skin, icon: Icons.map_outlined)),
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: RouteMapWidget(points: data.gpsPoints, maxHR: _hrMax > 0 ? _hrMax : null),
          )),
          // Desnivel si disponible
          if (hasElev)
            SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: _ElevationChips(
                skin:     skin,
                gainM:    data.elevGainM ?? 0,
                lossM:    data.elevLossM ?? 0,
                fastestKm: data.fastestKmPace != null
                    ? _fmtPace(data.fastestKmPace!) : null,
              ),
            )),
        ],

        // ── Distribución de zonas FC ──────────────────────────
        if (zones.isNotEmpty && _durMin > 0) ...[
          SliverToBoxAdapter(child: _SectionHeader('Zonas de frecuencia cardíaca', skin, icon: Icons.monitor_heart_outlined)),
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _ZoneDistribution(skin: skin, zonesSec: zones, totalSec: _durMin * 60),
          )),
        ],

        // ── Plan vs Real ──────────────────────────────────────
        if (_planMin > 0) ...[
          SliverToBoxAdapter(child: _SectionHeader('Plan vs realidad', skin, icon: Icons.compare_arrows)),
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _PlanVsReal(
              skin:      skin,
              planMin:   _planMin,
              realMin:   _durMin,
              planDistM: _planDistM,
              realDistM: (_distKm * 1000).round(),
            ),
          )),
        ],

        // ── Carga + carga del entrenamiento ──────────────────
        if (data.trainingLoad != null && data.trainingLoad! > 0) ...[
          SliverToBoxAdapter(child: _SectionHeader('Carga del entrenamiento', skin, icon: Icons.battery_charging_full_outlined)),
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _TrainingLoadCard(skin: skin, trimp: data.trainingLoad!),
          )),
        ],

        // ── RPE y sensaciones ─────────────────────────────────
        if (_rpe > 0 || energy != null) ...[
          SliverToBoxAdapter(child: _SectionHeader('Cómo te sentiste', skin, icon: Icons.mood_outlined)),
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _FeelingsCard(skin: skin, rpe: _rpe, energy: energy, notes: notes),
          )),
        ],

        // ── Mensaje motivacional ──────────────────────────────
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: _MotivationalCard(skin: skin, message: _motivationalMsg()),
        )),

        // ── Botones de acción ─────────────────────────────────
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
          child: Column(children: [
            // Alto MÍNIMO, no fijo: con la letra del sistema grande, 52 px
            // recortaban el texto del botón por arriba y por abajo.
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => context.go('/'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                icon: const Icon(Icons.home_outlined),
                label: const Text('Volver al inicio', maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => context.go('/plan'),
              icon: Icon(Icons.calendar_today_outlined, color: skin.textMuted, size: 16),
              label: Text('Ver plan de la semana',
                  style: TextStyle(color: skin.textMuted, fontSize: 13)),
            ),
          ]),
        )),
      ],
    );
  }
}

// ── Hero Banner ──────────────────────────────────────────────────
class _HeroBanner extends StatelessWidget {
  final SkinConfig skin;
  final String title, type, dateStr, timeStr;
  final String? sport;
  /// Sesión que NO se llegó a hacer. Sin esto, abrir una sesión perdida desde
  /// Inicio, Plan o Historial mostraba un check verde y "SESIÓN COMPLETADA":
  /// la app felicitaba al atleta justo por el día que falló.
  final bool missed;
  const _HeroBanner({required this.skin, required this.title,
      required this.type, required this.dateStr, required this.timeStr,
      this.sport, this.missed = false});

  // ⚠️ Antes esto eran EMOJIS DE CUADRADOS DE COLORES (🟩🟦🟧⬛🟫) delante del
  // título. En pantalla, un rodaje de base salía como un cuadrado azul junto a
  // "Rodaje aeróbico": parecía un icono roto, no un tipo de sesión. Ahora cada
  // tipo tiene su nombre y su icono, y van en una etiqueta bajo el título.
  static const _tipoNombre = {
    'recuperacion': 'Recuperación', 'base': 'Base aeróbica',
    'umbral': 'Umbral', 'vo2max': 'VO₂ máx', 'neuromuscular': 'Neuromuscular',
    'largo': 'Tirada larga', 'fuerza': 'Fuerza', 'hiit': 'Series HIIT',
    'competicion': 'Competición', 'fartlek': 'Fartlek', 'progresion': 'Progresivo',
  };
  static const _tipoIcono = {
    'recuperacion': Icons.self_improvement, 'base': Icons.terrain_outlined,
    'umbral': Icons.speed_outlined, 'vo2max': Icons.whatshot_outlined,
    'neuromuscular': Icons.bolt_outlined, 'largo': Icons.timeline,
    'fuerza': Icons.fitness_center, 'hiit': Icons.flash_on_outlined,
    'competicion': Icons.emoji_events_outlined, 'fartlek': Icons.waves_outlined,
    'progresion': Icons.trending_up,
  };
  static const _sportNombre = {
    'running': 'Carrera', 'cycling': 'Ciclismo', 'trail': 'Trail',
    'swimming': 'Natación', 'triathlon': 'Triatlón', 'rowing': 'Remo', 'gym': 'Gimnasio',
  };
  static const _sportIcono = {
    'running': Icons.directions_run, 'cycling': Icons.directions_bike,
    'trail': Icons.terrain, 'swimming': Icons.pool, 'triathlon': Icons.emoji_events,
    'rowing': Icons.rowing, 'gym': Icons.fitness_center,
  };

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    decoration: BoxDecoration(
      // Los `stops` no estaban y el degradado empezaba a aclararse desde arriba.
      // Todo el texto va en blanco: si el fondo ya se ha ido al color de la piel
      // —que en la piel clara es casi blanco— el título desaparece. Ahora el
      // verde aguanta hasta el 82 % y solo funde en el último tramo, ya vacío.
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: const [0.0, 0.93, 1.0],
        colors: [
          missed ? const Color(0xFF4E342E) : const Color(0xFF16521A),
          missed ? const Color(0xFF5D4037) : const Color(0xFF1B5E20),
          skin.background,
        ],
      ),
    ),
    child: SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(children: [
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: const Icon(Icons.arrow_back, color: Colors.white70),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: missed ? const Color(0xFF795548) : const Color(0xFF2E7D32),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(
                color: (missed ? const Color(0xFFA1887F) : const Color(0xFF4CAF50))
                    .withValues(alpha: 0.4),
                blurRadius: 20, spreadRadius: 4,
              )],
            ),
            child: Icon(missed ? Icons.event_busy : Icons.check,
                color: Colors.white, size: 40),
          ),
          const SizedBox(height: 14),
          // ⚠️ ESTE RÓTULO ERA VERDE CLARO (#81C784) SOBRE VERDE OSCURO (#1B5E20).
          //
          // Con 11 px, tracking de 3 y ese contraste, "SESIÓN COMPLETADA" casi no
          // se leía — se fundía con el fondo. Ahora va en una píldora clara sobre
          // el verde: el contraste deja de depender del punto exacto del degradado
          // donde caiga el texto.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
            ),
            child: Text(missed ? 'NO REALIZADA' : 'COMPLETADA',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800, letterSpacing: 1.6)),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white,
                fontSize: 20, fontWeight: FontWeight.w800, height: 1.2),
          ),
          const SizedBox(height: 10),
          // Tipo de sesión y deporte, cada uno con su icono. Wrap para que a
          // letra grande el segundo baje de línea en vez de desbordar.
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8, runSpacing: 8,
            children: [
              if (_tipoNombre[type] != null)
                _HeroTag(icon: _tipoIcono[type] ?? Icons.fitness_center,
                    text: _tipoNombre[type]!),
              if (_sportNombre[sport ?? ''] != null)
                _HeroTag(icon: _sportIcono[sport] ?? Icons.directions_run,
                    text: _sportNombre[sport]!),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '$dateStr${timeStr.isNotEmpty ? ' · $timeStr' : ''}',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            // Era white60 y sobre el degradado quedaba ilegible. El blanco al 85 %
            // se lee tanto en la parte oscura como donde ya está desvaneciendo.
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.88), fontSize: 13),
          ),
        ]),
      ),
    ),
  );
}

/// Etiqueta del hero: icono + texto, en blanco translúcido sobre el verde.
class _HeroTag extends StatelessWidget {
  final IconData icon;
  final String   text;
  const _HeroTag({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 15, color: Colors.white.withValues(alpha: 0.9)),
      const SizedBox(width: 6),
      Text(text, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 12,
              fontWeight: FontWeight.w600)),
    ]),
  );
}

// ── Métricas principales ─────────────────────────────────────────
class _MetricsGrid extends StatelessWidget {
  final SkinConfig skin;
  final int    durMin, hrAvg, hrMax, estCal;
  final double distKm;
  final String pace;
  final double? elevGainM;
  final int?    cadenceAvg;
  final double? trainingLoad;

  final Sport sport;
  const _MetricsGrid({
    required this.skin,   required this.durMin,  required this.distKm,
    required this.hrAvg,  required this.hrMax,   required this.pace,
    required this.estCal, required this.sport,
    this.elevGainM, this.cadenceAvg, this.trainingLoad,
  });

  @override
  Widget build(BuildContext context) {
    // Etiquetas en Capital y NÚMERO SEPARADO DE LA UNIDAD. Ver _MetricCard: con la
    // letra del sistema al 180 % (la que usa David), "10.14km" se partía en dos
    // renglones y "DURACIÓN" perdía la Ñ final.
    final items = [
      _MetricItem(icon: Icons.timer_outlined,     color: skin.accent,
          label: 'Duración',  value: durMin > 0 ? '$durMin' : '--', unit: durMin > 0 ? 'min' : ''),
      // Nadando se cuentan metros (1.500 m), no "1,50 km"
      _MetricItem(icon: Icons.straighten,          color: const Color(0xFF42A5F5),
          label: 'Distancia',
          value: distKm > 0
              ? (sport == Sport.natacion
                  ? '${(distKm * 1000).round()}'
                  : distKm.toStringAsFixed(2).replaceAll('.', ','))
              : '--',
          unit: distKm > 0 ? (sport == Sport.natacion ? 'm' : 'km') : ''),
      _MetricItem(icon: Icons.favorite_outline,    color: const Color(0xFFEF5350),
          label: 'FC media',  value: hrAvg > 0 ? '$hrAvg' : '--', unit: hrAvg > 0 ? 'ppm' : ''),
      _MetricItem(icon: Icons.arrow_upward,        color: const Color(0xFFF44336),
          label: 'FC máx',    value: hrMax > 0 ? '$hrMax' : '--', unit: hrMax > 0 ? 'ppm' : ''),
      _MetricItem(icon: Icons.speed_outlined,      color: const Color(0xFF26C6DA),
          label: sport.speedLabel.isEmpty ? 'Ritmo' : _capitalizar(sport.speedLabel),
          value: pace == '--' ? '--' : pace,
          unit: pace == '--' ? '' : sport.speedUnit.trim()),
      _MetricItem(icon: Icons.local_fire_department_outlined, color: const Color(0xFFFF9800),
          label: 'Calorías',  value: estCal > 0 ? '~$estCal' : '--', unit: estCal > 0 ? 'kcal' : ''),
      if (elevGainM != null && elevGainM! > 0)
        _MetricItem(icon: Icons.trending_up,       color: const Color(0xFF66BB6A),
            label: 'Desnivel', value: '+${elevGainM!.round()}', unit: 'm'),
      if (cadenceAvg != null && cadenceAvg! > 0)
        _MetricItem(icon: Icons.directions_run,    color: const Color(0xFFAB47BC),
            label: 'Cadencia',  value: '$cadenceAvg', unit: 'ppm'),
    ];

    // COLUMNAS SEGÚN EL TAMAÑO DE LETRA DEL SISTEMA.
    //
    // Tres columnas en un móvil son ~105 px por celda. Con la letra al 180 % no
    // cabe ni "Duración". En vez de recortar la accesibilidad, se le da más ancho
    // a cada tarjeta: dos columnas cuando la letra es grande.
    final escala  = MediaQuery.textScalerOf(context).scale(14) / 14;
    final columnas = escala >= 1.3 ? 2 : 3;
    // Y la celda crece a lo alto con la letra, para que el número no se ahogue.
    final alto = columnas == 2 ? 2.6 : 1.45;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columnas,
          childAspectRatio: alto / (escala.clamp(1.0, 1.8)),
          crossAxisSpacing: 10, mainAxisSpacing: 10,
        ),
        itemCount: items.length,
        itemBuilder: (_, i) => _MetricCard(skin: skin, item: items[i]),
      ),
    );
  }
}

/// "RITMO MEDIO" → "Ritmo medio". Las etiquetas en MAYÚSCULAS ocupan más y se
/// leen peor; el dato ya destaca por tamaño, no hace falta gritar.
String _capitalizar(String s) {
  final t = s.trim().toLowerCase();
  return t.isEmpty ? t : '${t[0].toUpperCase()}${t.substring(1)}';
}

class _MetricItem {
  final IconData icon;
  final Color    color;
  final String   label;
  /// El número, SIN la unidad: "61", "10,14", "144".
  final String   value;
  /// La unidad, aparte: "min", "km", "bpm". Ver _MetricCard para el porqué.
  final String   unit;
  const _MetricItem({required this.icon, required this.color,
      required this.label, required this.value, this.unit = ''});
}

/// Una métrica de la sesión.
///
/// ⚠️ POR QUÉ ESTÁ ASÍ (08/08/2026)
///
/// David tiene la letra del sistema **al 180 %** —cosa nada rara a los 52 años— y
/// esta tarjeta se rompía entera: "DURACIÓN" salía como "DURACIÓ / N", "10.14km"
/// como "10.14k / m" y "CALORÍAS" como "CALORÍA / S". El texto no tenía ni
/// maxLines, ni ellipsis, ni forma de encoger: simplemente se partía.
///
/// Tres decisiones para que aguante:
///
///  1. **El número y la unidad van separados.** "10,14" grande y "km" pequeño
///     debajo. Antes competían por el mismo renglón y ganaba el corte.
///  2. **FittedBox en el número**: si no cabe, se encoge en vez de partirse.
///  3. **La etiqueta en Capital, no en MAYÚSCULAS con tracking.** "Duración" ocupa
///     un 25 % menos que "D U R A C I Ó N" y se lee mejor de un vistazo.
class _MetricCard extends StatelessWidget {
  final SkinConfig skin;
  final _MetricItem item;
  const _MetricCard({required this.skin, required this.item});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    decoration: BoxDecoration(
      color: skin.backgroundCard,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: item.color.withValues(alpha: 0.22)),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(item.icon, color: item.color, size: 16),
          const SizedBox(width: 5),
          Expanded(
            child: Text(item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: skin.textMuted, fontSize: 11,
                    fontWeight: FontWeight.w600, height: 1.1)),
          ),
        ]),
        const SizedBox(height: 7),
        // El número manda: se le da todo el ancho y se encoge antes que partirse.
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(item.value,
                    maxLines: 1,
                    style: TextStyle(color: skin.textPrimary,
                        fontSize: 21, fontWeight: FontWeight.w700, height: 1)),
              ),
            ),
            if (item.unit.isNotEmpty) ...[
              const SizedBox(width: 3),
              Text(item.unit,
                  maxLines: 1,
                  style: TextStyle(color: skin.textMuted,
                      fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      ],
    ),
  );
}

// ── Gráfico de ritmo por km (BarChart fl_chart) ──────────────────
class _PaceChart extends StatelessWidget {
  final SkinConfig        skin;
  final List<_PaceSplit>  splits;
  final int               hrMax;

  const _PaceChart({required this.skin, required this.splits, required this.hrMax});

  Color _barColor(int paceSec, int hrAvg) {
    // Color basado en zona HR si disponible, si no por ritmo
    if (hrAvg > 0 && hrMax > 0) {
      final pct = hrAvg / hrMax;
      if (pct < 0.60) return const Color(0xFF4CAF50);
      if (pct < 0.70) return const Color(0xFF8BC34A);
      if (pct < 0.80) return const Color(0xFFFFEB3B);
      if (pct < 0.90) return const Color(0xFFFF9800);
      return const Color(0xFFF44336);
    }
    // Fallback: shades from green (fast) to red (slow)
    final minP = splits.map((s) => s.paceSec).reduce(math.min);
    final maxP = splits.map((s) => s.paceSec).reduce(math.max);
    if (maxP == minP) return const Color(0xFF42A5F5);
    final t = (paceSec - minP) / (maxP - minP);
    return Color.lerp(const Color(0xFF4CAF50), const Color(0xFFF44336), t)!;
  }

  String _fmtPace(double v) {
    final s = v.round();
    return "${s ~/ 60}'${(s % 60).toString().padLeft(2, '0')}\"";
  }

  @override
  Widget build(BuildContext context) {
    final maxPace = splits.map((s) => s.paceSec).reduce(math.max).toDouble();
    final minPace = splits.map((s) => s.paceSec).reduce(math.min).toDouble();
    final topY    = maxPace + (maxPace - minPace) * 0.15 + 30;
    final botY    = math.max(0.0, minPace - 30);

    final bars = splits.asMap().entries.map((e) {
      final i = e.key;
      final s = e.value;
      return BarChartGroupData(
        x: i,
        barRods: [BarChartRodData(
          toY:       s.paceSec.toDouble(),
          fromY:     botY,
          color:     _barColor(s.paceSec, s.hrAvg),
          width:     splits.length > 10 ? 14 : 22,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
        )],
      );
    }).toList();

    // Un gráfico es un dibujo, no un texto corrido: si sus rótulos crecen al
    // 180 % como el resto de la app, "8'15\"" se parte en dos renglones y las
    // barras se quedan sin sitio. Se limita el aumento a un 15 % y se le da más
    // alto al recuadro para compensar.
    const escalaEje = TextScaler.linear(1.15);
    final escala = MediaQuery.textScalerOf(context).scale(14) / 14;

    return Container(
      height: 180 + (escala.clamp(1.0, 1.8) - 1.0) * 40,
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
      decoration: BoxDecoration(
        color: skin.backgroundCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: BarChart(
        BarChartData(
          maxY: topY, minY: botY,
          barGroups: bars,
          gridData: FlGridData(
            show: true,
            horizontalInterval: 60,
            checkToShowVerticalLine: (_) => false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: skin.border.withValues(alpha: 0.5), strokeWidth: 0.8),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true, reservedSize: 48,
                interval: 60,
                getTitlesWidget: (v, _) => Text(
                  _fmtPace(v),
                  textScaler: escalaEje,
                  maxLines: 1, softWrap: false,
                  style: TextStyle(color: skin.textMuted, fontSize: 10),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true, reservedSize: 24,
                getTitlesWidget: (v, _) {
                  final idx = v.round();
                  if (idx < 0 || idx >= splits.length) return const SizedBox.shrink();
                  return Text('K${splits[idx].km}',
                    textScaler: escalaEje,
                    maxLines: 1, softWrap: false,
                    style: TextStyle(color: skin.textMuted, fontSize: 10));
                },
              ),
            ),
            topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => skin.backgroundSecondary,
              getTooltipItem: (group, _, rod, __) {
                final s = splits[group.x];
                final pace = _fmtPace(rod.toY);
                final hr   = s.hrAvg > 0 ? '\n♥ ${s.hrAvg} ppm' : '';
                return BarTooltipItem(
                  'K${s.km} · $pace$hr',
                  TextStyle(color: skin.textPrimary, fontSize: 11,
                      fontWeight: FontWeight.w600),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ── Tabla de splits ──────────────────────────────────────────────
class _SplitsTable extends StatelessWidget {
  final SkinConfig       skin;
  final List<_PaceSplit> splits;
  final String Function(int) fmtPace;

  const _SplitsTable({required this.skin, required this.splits, required this.fmtPace});

  @override
  Widget build(BuildContext context) {
    final best = splits.isNotEmpty
        ? splits.reduce((a, b) => a.paceSec < b.paceSec ? a : b).km : -1;

    return Container(
      decoration: BoxDecoration(
        color: skin.backgroundCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: [
        // Cabecera
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(children: [
            _SplitCell('Km',     flex: 2, color: skin.textMuted, header: true),
            _SplitCell('Ritmo',  flex: 5, color: skin.textMuted, header: true, alignRight: true),
            _SplitCell('Pulso',  flex: 4, color: skin.textMuted, header: true, alignRight: true),
          ]),
        ),
        Divider(color: skin.border, height: 1),
        // Filas
        //
        // Las tres columnas van en Expanded con recorte: la etiqueta "BEST"
        // empujaba el pulso fuera de la pantalla y el mejor kilómetro salía
        // "144bp". Ahora el mejor se marca con una estrella, que ocupa un tercio
        // y se entiende igual.
        ...splits.map((s) {
          final isBest = s.km == best;
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
            child: Row(children: [
              _SplitCell('${s.km}', flex: 2, color: skin.textMuted),
              Expanded(flex: 5, child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (isBest) ...[
                    const Icon(Icons.star_rounded,
                        size: 17, color: Color(0xFF4CAF50)),
                    const SizedBox(width: 4),
                  ],
                  Flexible(child: Text(fmtPace(s.paceSec),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: isBest ? const Color(0xFF4CAF50) : skin.textPrimary,
                      fontSize: 14, fontWeight: FontWeight.w700,
                    ))),
                ],
              )),
              const SizedBox(width: 6),
              Expanded(flex: 4, child: Text(
                s.hrAvg > 0 ? '${s.hrAvg} ppm' : '--',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(color: skin.textSecondary, fontSize: 13),
              )),
            ]),
          );
        }),
        const SizedBox(height: 4),
      ]),
    );
  }
}

class _SplitCell extends StatelessWidget {
  final String text;
  final int    flex;
  final Color  color;
  final bool   header;
  final bool   alignRight;
  const _SplitCell(this.text, {required this.flex, required this.color,
      this.header = false, this.alignRight = false});

  @override
  Widget build(BuildContext context) => Expanded(
    flex: flex,
    child: Text(text,
      textAlign: alignRight ? TextAlign.right : TextAlign.left,
      maxLines: 1, overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: color,
        fontSize: header ? 11 : 13,
        fontWeight: header ? FontWeight.w600 : FontWeight.w500,
      ),
    ),
  );
}

// ── Chips de elevación ───────────────────────────────────────────
class _ElevationChips extends StatelessWidget {
  final SkinConfig skin;
  final double gainM, lossM;
  final String? fastestKm;

  const _ElevationChips({required this.skin, required this.gainM,
      required this.lossM, this.fastestKm});

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8, runSpacing: 8,
    children: [
      if (gainM > 0) _Chip(
        label: '+${gainM.round()} m',
        icon: Icons.trending_up,
        color: const Color(0xFF66BB6A),
        skin: skin,
      ),
      if (lossM > 0) _Chip(
        label: '−${lossM.round()} m',
        icon: Icons.trending_down,
        color: const Color(0xFFEF5350),
        skin: skin,
      ),
      // El rayo sobraba: el chip ya lleva su icono.
      if (fastestKm != null) _Chip(
        label: 'Mejor km $fastestKm',
        icon: Icons.flash_on,
        color: const Color(0xFFFFD54F),
        skin: skin,
      ),
    ],
  );
}

class _Chip extends StatelessWidget {
  final SkinConfig skin;
  final String    label;
  final IconData  icon;
  final Color     color;
  const _Chip({required this.skin, required this.label,
      required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: color, size: 15),
      const SizedBox(width: 5),
      Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700))),
    ]),
  );
}

// ── Distribución de zonas FC ─────────────────────────────────────
class _ZoneDistribution extends StatelessWidget {
  final SkinConfig     skin;
  final Map<String, int> zonesSec;
  final int            totalSec;

  const _ZoneDistribution({required this.skin, required this.zonesSec, required this.totalSec});

  static const _zColors = {
    'Z1': Color(0xFF81C784), 'Z2': Color(0xFF4CAF50),
    'Z3': Color(0xFFFFEB3B), 'Z4': Color(0xFFFF9800), 'Z5': Color(0xFFF44336),
  };
  // Las SEIS del entrenador. Del verde de recuperación al rojo del máximo,
  // en el mismo orden de intensidad que las genéricas.
  static const _rColors = {
    'R0': Color(0xFF81C784), 'R1': Color(0xFF4CAF50), 'R1+': Color(0xFFA3E635),
    'R2': Color(0xFFFFEB3B), 'R3': Color(0xFFFF9800), 'R3+': Color(0xFFF44336),
  };
  static const _zLabels = {
    'Z1': 'Recuperación  <60%',
    'Z2': 'Base aeróbica  60–70%',
    'Z3': 'Aeróbico mod.  70–80%',
    'Z4': 'Umbral láctico  80–90%',
    'Z5': 'VO₂max / Máx  >90%',
  };
  // ⚠️ Las de arriba son la escala GENÉRICA por % de FC máxima, que es la que
  // tienen las salidas guardadas antes del 07/08. Su entrenador no trabaja así:
  // usa seis zonas propias sobre umbrales ventilatorios. Con la escala vieja, un
  // rodaje aeróbico a 144 ppm aparecía como "40 minutos en umbral láctico".
  static const _rLabels = {
    'R0': 'Recuperación activa',
    'R1': 'Aeróbico extensivo',
    'R1+': 'Aeróbico intensivo (VT1)',
    'R2': 'Entre VT1 y VT2',
    'R3': 'En torno a VT2',
    'R3+': 'Máxima',
  };

  bool get _sonDelEntrenador => zonesSec.keys.any((k) => _rLabels.containsKey(k));
  Color _colorDe(String k) => (_sonDelEntrenador ? _rColors[k] : _zColors[k]) ?? Colors.grey;
  String? _etiquetaDe(String k) => _sonDelEntrenador ? _rLabels[k] : _zLabels[k];

  @override
  Widget build(BuildContext context) {
    final active = zonesSec.entries.where((e) => e.value > 0).toList();
    if (active.isEmpty) return const SizedBox.shrink();
    final total = math.max(1, zonesSec.values.fold(0, (a, b) => a + b));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: skin.backgroundCard, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Barra apilada
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 14,
            child: Row(
              children: active.map((e) => Expanded(
                flex: e.value,
                child: Container(color: _colorDe(e.key)),
              )).toList(),
            ),
          ),
        ),
        const SizedBox(height: 14),
        // Filas por zona
        ...zonesSec.entries.map((e) {
          final sec  = e.value;
          if (sec <= 0) return const SizedBox.shrink();
          final min  = (sec / 60).round();
          final pct  = (sec / total * 100).round();
          final clr  = _colorDe(e.key);
          // Sobre el color de la zona, el texto en blanco o en negro según lo
          // clara que sea: la R2 es amarilla y en blanco no se leería.
          final sobre = clr.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // La clave y el tiempo arriba; la descripción, en su propia línea.
                // Todo en una sola fila no cabía con la letra del sistema grande.
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: clr, borderRadius: BorderRadius.circular(20)),
                    child: Text(e.key, maxLines: 1, style: TextStyle(
                        color: sobre, fontSize: 11, fontWeight: FontWeight.w900)),
                  ),
                  const Spacer(),
                  Text('$min min · $pct %', maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: skin.textPrimary,
                          fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 4),
                Text(_etiquetaDe(e.key) ?? '', maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: skin.textMuted, fontSize: 12)),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: sec / total,
                    backgroundColor: skin.border,
                    valueColor: AlwaysStoppedAnimation(clr),
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          );
        }),
      ]),
    );
  }
}

// ── Plan vs Real ─────────────────────────────────────────────────
class _PlanVsReal extends StatelessWidget {
  final SkinConfig skin;
  final int planMin, realMin, planDistM, realDistM;
  const _PlanVsReal({required this.skin, required this.planMin,
      required this.realMin, required this.planDistM, required this.realDistM});

  Color _badge(int pct) {
    if (pct >= 95) return const Color(0xFF4CAF50);
    if (pct >= 80) return const Color(0xFFFFA726);
    return const Color(0xFFEF5350);
  }

  @override
  Widget build(BuildContext context) {
    final durPct  = planMin  > 0 ? (realMin  / planMin  * 100).round() : 0;
    final distPct = planDistM > 0 ? (realDistM / planDistM * 100).round() : 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: skin.backgroundCard, borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        _CompareRow(skin: skin, label: 'Duración',
            plan: '$planMin min', real: realMin > 0 ? '$realMin min' : '--',
            pct: durPct, color: _badge(durPct)),
        if (planDistM > 0) ...[
          Divider(color: skin.border, height: 20),
          _CompareRow(skin: skin, label: 'Distancia',
              plan: '${(planDistM / 1000).toStringAsFixed(1).replaceAll('.', ',')} km',
              real: realDistM > 0
                  ? '${(realDistM / 1000).toStringAsFixed(2).replaceAll('.', ',')} km'
                  : '--',
              pct: distPct, color: _badge(distPct)),
        ],
      ]),
    );
  }
}

class _CompareRow extends StatelessWidget {
  final SkinConfig skin;
  final String label, plan, real;
  final int pct;
  final Color color;
  const _CompareRow({required this.skin, required this.label,
      required this.plan, required this.real, required this.pct, required this.color});

  // Antes iba todo en una sola fila: etiqueta, previsto, flecha, real y el
  // porcentaje. Con la letra grande no cabía y "Duración" se partía por la mitad.
  // Ahora la etiqueta y el porcentaje van arriba, y la comparación debajo con
  // sitio de sobra.
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [
        Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: skin.textMuted, fontSize: 12,
                fontWeight: FontWeight.w600))),
        if (pct > 0) Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Text('$pct %', maxLines: 1,
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
        ),
      ]),
      const SizedBox(height: 5),
      // Wrap para que, si la letra es enorme, el resultado baje de línea en vez
      // de comerse la unidad.
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8, runSpacing: 2,
        children: [
          Text(plan, style: TextStyle(color: skin.textMuted, fontSize: 14)),
          Icon(Icons.arrow_forward, color: skin.textMuted.withValues(alpha: 0.7), size: 15),
          Text(real, style: TextStyle(color: skin.textPrimary,
              fontSize: 16, fontWeight: FontWeight.w800)),
        ],
      ),
    ],
  );
}

// ── Carga de entrenamiento (TRIMP) ───────────────────────────────
class _TrainingLoadCard extends StatelessWidget {
  final SkinConfig skin;
  final double trimp;
  const _TrainingLoadCard({required this.skin, required this.trimp});

  String get _level {
    if (trimp < 30) return 'Baja';
    if (trimp < 60) return 'Moderada';
    if (trimp < 100) return 'Alta';
    return 'Muy alta';
  }
  Color get _color {
    if (trimp < 30) return const Color(0xFF4CAF50);
    if (trimp < 60) return const Color(0xFFFFEB3B);
    if (trimp < 100) return const Color(0xFFFF9800);
    return const Color(0xFFF44336);
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: skin.backgroundCard, borderRadius: BorderRadius.circular(12)),
    child: Row(children: [
      Container(
        width: 56, height: 56,
        decoration: BoxDecoration(
          color: _color.withValues(alpha: 0.12),
          shape: BoxShape.circle,
          border: Border.all(color: _color.withValues(alpha: 0.4), width: 2),
        ),
        // El círculo tiene un tamaño fijo: el número se encoge para caber en
        // vez de recortarse cuando la letra del sistema es grande.
        child: Center(child: Padding(
          padding: const EdgeInsets.all(6),
          child: FittedBox(fit: BoxFit.scaleDown, child: Text(trimp.round().toString(),
            style: TextStyle(color: _color, fontSize: 18, fontWeight: FontWeight.w800))),
        )),
      ),
      const SizedBox(width: 16),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Carga ${_level.toLowerCase()}', maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: skin.textPrimary, fontSize: 14,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            'Índice de carga basado en frecuencia cardíaca y duración. '
            'Guía al agente IA para calcular tu próxima sesión óptima.',
            style: TextStyle(color: skin.textMuted, fontSize: 11, height: 1.4),
          ),
        ],
      )),
    ]),
  );
}

// ── Sensaciones ──────────────────────────────────────────────────
class _FeelingsCard extends StatelessWidget {
  final SkinConfig skin;
  final int        rpe;
  final int?       energy;
  final String?    notes;
  const _FeelingsCard({required this.skin, required this.rpe,
      this.energy, this.notes});

  static const _rpeLabels = {
    1: 'Muy suave', 2: 'Suave', 3: 'Moderado', 4: 'Algo duro',
    5: 'Duro', 6: 'Duro+', 7: 'Muy duro', 8: 'Muy muy duro',
    9: 'Extremo', 10: 'Máximo absoluto',
  };

  Color _rpeColor(SkinConfig s) {
    if (rpe <= 3) return s.success;
    if (rpe <= 6) return s.warning;
    return s.error;
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: skin.backgroundCard, borderRadius: BorderRadius.circular(12)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Expanded: las dos cajas se reparten el ancho a partes iguales. Sin él
      // se ajustaban al texto y "Máximo absoluto" desbordaba la fila.
      if (rpe > 0) IntrinsicHeight(child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // "Esfuerzo (RPE)" no cabía en media pantalla y salía "Esfuerzo (...".
          Expanded(child: _FeelingDot(label: 'Esfuerzo', value: '$rpe',
              unit: '/10',
              sublabel: _rpeLabels[rpe] ?? '', color: _rpeColor(skin), skin: skin)),
          if (energy != null) ...[
            const SizedBox(width: 12),
            Expanded(child: _FeelingDot(label: 'Energía', value: '$energy',
                unit: '/5',
                sublabel: energy! >= 4 ? 'Muy bien' : energy! >= 3 ? 'Regular' : 'Cansado',
                color: energy! >= 4 ? skin.success : energy! >= 3 ? skin.warning : skin.error,
                skin: skin)),
          ],
        ],
      )),
      if (notes != null && notes!.isNotEmpty) ...[
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: skin.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: skin.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.edit_note, size: 15, color: skin.textMuted),
              const SizedBox(width: 5),
              Expanded(child: Text('Tus notas', maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: skin.textMuted, fontSize: 11,
                      fontWeight: FontWeight.w600))),
            ]),
            const SizedBox(height: 6),
            Text(notes!, style: TextStyle(color: skin.textSecondary, fontSize: 13)),
          ]),
        ),
      ],
    ]),
  );
}

class _FeelingDot extends StatelessWidget {
  final SkinConfig skin;
  final String label, value, sublabel, unit;
  final Color  color;
  const _FeelingDot({required this.skin, required this.label,
      required this.value, required this.sublabel, required this.color,
      this.unit = ''});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(label, textAlign: TextAlign.center, maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: skin.textMuted, fontSize: 11,
              fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      // El "/10" pequeño al lado del número: así el dato manda y la escala
      // acompaña, en vez de competir por el mismo tamaño.
      FittedBox(fit: BoxFit.scaleDown, child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: TextStyle(
              color: color, fontSize: 24, fontWeight: FontWeight.w900, height: 1)),
          if (unit.isNotEmpty) Text(unit, style: TextStyle(
              color: color.withValues(alpha: 0.75), fontSize: 13,
              fontWeight: FontWeight.w700)),
        ],
      )),
      const SizedBox(height: 3),
      Text(sublabel, textAlign: TextAlign.center, maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: skin.textSecondary, fontSize: 11)),
    ]),
  );
}

// ── Mensaje motivacional ─────────────────────────────────────────
class _MotivationalCard extends StatelessWidget {
  final SkinConfig skin;
  final String     message;
  const _MotivationalCard({required this.skin, required this.message});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [
        skin.accent.withValues(alpha: 0.15),
        skin.accentSecondary.withValues(alpha: 0.08),
      ]),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: skin.accent.withValues(alpha: 0.3)),
    ),
    child: Row(children: [
      const Text('🏅', style: TextStyle(fontSize: 32)),
      const SizedBox(width: 14),
      Expanded(child: Text(message, style: TextStyle(
          color: skin.textPrimary, fontSize: 14,
          fontWeight: FontWeight.w600, height: 1.4))),
    ]),
  );
}

// ── Section header ───────────────────────────────────────────────
// Encabezado de sección: barra del color de la marca, icono y título.
//
// Antes era un texto gris de 10 px en MAYÚSCULAS con letterSpacing 2 — se perdía
// contra el fondo y, con la letra del sistema grande, "ZONAS DE FRECUENCIA
// CARDÍACA" se comía a sí mismo. Ahora la sección se distingue de un vistazo.
class _SectionHeader extends StatelessWidget {
  final String     text;
  final SkinConfig skin;
  final IconData?  icon;
  const _SectionHeader(this.text, this.skin, {this.icon});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 26, 16, 12),
    child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Container(
        width: 3, height: 18,
        decoration: BoxDecoration(
          color: skin.accent, borderRadius: BorderRadius.circular(2)),
      ),
      const SizedBox(width: 9),
      if (icon != null) ...[
        Icon(icon, size: 16, color: skin.accent),
        const SizedBox(width: 7),
      ],
      Expanded(child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: skin.textPrimary, fontSize: 14,
              fontWeight: FontWeight.w800, letterSpacing: 0.1))),
    ]),
  );
}


// ── Tabla "por bloques" ───────────────────────────────────────────
//
// Cada fila es un bloque con lo que dio: tiempo real frente al previsto,
// kilómetros, ritmo y pulso. Los bloques sin distancia (fuerza, movilidad) no
// muestran km ni ritmo en vez de enseñar un cero, que se leería como un fallo.
class _TablaBloques extends StatelessWidget {
  final SkinConfig skin;
  final List<Map<String, dynamic>> bloques;
  final String Function(int) fmtPace;
  const _TablaBloques({required this.skin, required this.bloques, required this.fmtPace});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: skin.backgroundCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: skin.border),
      ),
      child: Column(
        children: List.generate(bloques.length, (i) {
          final b       = bloques[i];
          final nombre  = (b['block'] ?? 'Bloque ${i + 1}').toString();
          final zona    = b['zone']?.toString();
          final min     = _pi(b['min']);
          final prev    = _pi(b['min_previstos']);
          final metros  = _pi(b['distance_m']) ?? 0;
          final ritmo   = _pi(b['pace_sec_km']);
          final fc      = _pi(b['hr_avg']);

          final detalle = <String>[
            if (min != null) '$min min${prev != null && prev != min ? " (de $prev)" : ""}',
            if (metros >= 100) '${(metros / 1000).toStringAsFixed(2)} km',
            if (ritmo != null) '${fmtPace(ritmo)}/km',
            if (fc != null) '$fc ppm',
          ].join(' · ');

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              border: i == 0 ? null : Border(top: BorderSide(color: skin.border)),
            ),
            child: Row(
              children: [
                Container(
                  width: 26, height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: skin.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text('${i + 1}', style: TextStyle(
                      color: skin.accent, fontSize: 12, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Flexible(child: Text(nombre,
                            style: TextStyle(color: skin.textPrimary, fontSize: 13,
                                fontWeight: FontWeight.w600),
                            maxLines: 1, overflow: TextOverflow.ellipsis)),
                        if (zona != null && zona.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: skin.textMuted.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(zona, style: TextStyle(
                                color: skin.textMuted, fontSize: 10,
                                fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ]),
                      if (detalle.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(detalle, style: TextStyle(color: skin.textMuted, fontSize: 12)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}