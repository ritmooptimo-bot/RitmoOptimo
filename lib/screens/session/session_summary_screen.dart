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

    // HR zones from server (seconds per zone)
    final rawZones = gpsRaw['hr_zones_sec'] as Map?;
    if (rawZones != null && rawZones.isNotEmpty) {
      serverHrZones = {
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

  // Zonas HR: usa datos del servidor si disponibles, si no calcula desde puntos GPS
  Map<String, int> get _zoneSeconds {
    if (data.serverHrZones != null && data.serverHrZones!.isNotEmpty) {
      final z = data.serverHrZones!;
      final total = z.values.fold(0, (a, b) => a + b);
      if (total > 0) return z;
    }
    // Cálculo de fallback desde puntos GPS
    final maxHR  = _hrMax > 0 ? _hrMax.toDouble() : 190.0;
    final ptsHR  = data.gpsPoints.where((p) => p.hr != null && p.hr! > 0).toList();
    if (ptsHR.isNotEmpty) {
      final spp = (_durMin * 60) / ptsHR.length;
      int z1 = 0, z2 = 0, z3 = 0, z4 = 0, z5 = 0;
      for (final p in ptsHR) {
        final pct = p.hr! / maxHR;
        if      (pct < 0.60) z1 += spp.round();
        else if (pct < 0.70) z2 += spp.round();
        else if (pct < 0.80) z3 += spp.round();
        else if (pct < 0.90) z4 += spp.round();
        else                 z5 += spp.round();
      }
      return {'Z1': z1, 'Z2': z2, 'Z3': z3, 'Z4': z4, 'Z5': z5};
    }
    // Estimación desde FC media
    if (_hrAvg > 0 && _durMin > 0) {
      final total = _durMin * 60;
      final pct   = _hrAvg / maxHR;
      if (pct < 0.60) return {'Z1': total, 'Z2': 0, 'Z3': 0, 'Z4': 0, 'Z5': 0};
      if (pct < 0.70) return {'Z1': (total*.2).round(), 'Z2': (total*.8).round(), 'Z3': 0, 'Z4': 0, 'Z5': 0};
      if (pct < 0.80) return {'Z1': (total*.1).round(), 'Z2': (total*.2).round(), 'Z3': (total*.7).round(), 'Z4': 0, 'Z5': 0};
      if (pct < 0.90) return {'Z1': 0, 'Z2': (total*.1).round(), 'Z3': (total*.3).round(), 'Z4': (total*.6).round(), 'Z5': 0};
      return {'Z1': 0, 'Z2': 0, 'Z3': (total*.1).round(), 'Z4': (total*.4).round(), 'Z5': (total*.5).round()};
    }
    return {};
  }

  String _motivationalMsg() {
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
                  ? 'VELOCIDAD POR KILÓMETRO'
                  : 'RITMO POR KILÓMETRO', skin)),
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

        // ── Mapa de ruta ──────────────────────────────────────
        if (hasGPS) ...[
          SliverToBoxAdapter(child: _SectionHeader('RECORRIDO', skin)),
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
          SliverToBoxAdapter(child: _SectionHeader('ZONAS DE FRECUENCIA CARDÍACA', skin)),
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _ZoneDistribution(skin: skin, zonesSec: zones, totalSec: _durMin * 60),
          )),
        ],

        // ── Plan vs Real ──────────────────────────────────────
        if (_planMin > 0) ...[
          SliverToBoxAdapter(child: _SectionHeader('PLAN VS REALIDAD', skin)),
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
          SliverToBoxAdapter(child: _SectionHeader('CARGA DEL ENTRENAMIENTO', skin)),
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _TrainingLoadCard(skin: skin, trimp: data.trainingLoad!),
          )),
        ],

        // ── RPE y sensaciones ─────────────────────────────────
        if (_rpe > 0 || energy != null) ...[
          SliverToBoxAdapter(child: _SectionHeader('CÓMO TE SENTISTE', skin)),
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
            SizedBox(
              width: double.infinity, height: 52,
              child: ElevatedButton.icon(
                onPressed: () => context.go('/'),
                icon: const Icon(Icons.home_outlined),
                label: const Text('VOLVER AL INICIO',
                    style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1.5)),
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
  const _HeroBanner({required this.skin, required this.title,
      required this.type, required this.dateStr, required this.timeStr,
      this.sport});

  static const _typeIcons = {
    'recuperacion': '🟩', 'base': '🟦', 'umbral': '🟧', 'vo2max': '🔴',
    'neuromuscular': '⬛', 'largo': '🟫', 'fuerza': '⚫', 'hiit': '🩷',
    'competicion': '🏆', 'fartlek': '🌊', 'progresion': '📈',
  };
  static const _sportIcons = {
    'running': '🏃', 'cycling': '🚴', 'trail': '⛰️',
    'swimming': '🏊', 'triathlon': '🏅', 'rowing': '🚣', 'gym': '🏋️',
  };

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [const Color(0xFF1B5E20), skin.background],
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
              color: const Color(0xFF2E7D32),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(
                color: const Color(0xFF4CAF50).withValues(alpha: 0.4),
                blurRadius: 20, spreadRadius: 4,
              )],
            ),
            child: const Icon(Icons.check, color: Colors.white, size: 40),
          ),
          const SizedBox(height: 12),
          const Text('SESIÓN COMPLETADA', style: TextStyle(
              color: Color(0xFF81C784), fontSize: 11,
              fontWeight: FontWeight.w700, letterSpacing: 3)),
          const SizedBox(height: 8),
          Text(
            '${_typeIcons[type] ?? _sportIcons[sport ?? ''] ?? '🏃'} $title',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white,
                fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            '$dateStr${timeStr.isNotEmpty ? ' · $timeStr' : ''}',
            style: const TextStyle(color: Colors.white60, fontSize: 13),
          ),
        ]),
      ),
    ),
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
    final items = [
      _MetricItem(icon: Icons.timer_outlined,     color: skin.accent,
          label: 'DURACIÓN',  value: durMin > 0 ? '${durMin}min' : '--'),
      // Nadando se cuentan metros (1.500 m), no "1,50 km"
      _MetricItem(icon: Icons.straighten,          color: const Color(0xFF42A5F5),
          label: 'DISTANCIA',
          value: distKm > 0
              ? (sport == Sport.natacion
                  ? '${(distKm * 1000).round()}m'
                  : '${distKm.toStringAsFixed(2)}km')
              : '--'),
      _MetricItem(icon: Icons.favorite_outline,    color: const Color(0xFFEF5350),
          label: 'FC MEDIA',  value: hrAvg > 0 ? '${hrAvg}bpm' : '--'),
      _MetricItem(icon: Icons.arrow_upward,        color: const Color(0xFFF44336),
          label: 'FC MÁX',   value: hrMax > 0 ? '${hrMax}bpm' : '--'),
      _MetricItem(icon: Icons.speed_outlined,      color: const Color(0xFF26C6DA),
          label: sport.speedLabel.isEmpty ? 'RITMO' : sport.speedLabel,
          value: pace == '--' ? '--' : '$pace ${sport.speedUnit}'.trim()),
      _MetricItem(icon: Icons.local_fire_department_outlined, color: const Color(0xFFFF9800),
          label: 'CALORÍAS',  value: estCal > 0 ? '~${estCal}kcal' : '--'),
      if (elevGainM != null && elevGainM! > 0)
        _MetricItem(icon: Icons.trending_up,       color: const Color(0xFF66BB6A),
            label: 'DESNIVEL+', value: '+${elevGainM!.round()}m'),
      if (cadenceAvg != null && cadenceAvg! > 0)
        _MetricItem(icon: Icons.directions_run,    color: const Color(0xFFAB47BC),
            label: 'CADENCIA',  value: '${cadenceAvg}rpm'),
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, childAspectRatio: 1.1,
          crossAxisSpacing: 10, mainAxisSpacing: 10,
        ),
        itemCount: items.length,
        itemBuilder: (_, i) => _MetricCard(skin: skin, item: items[i]),
      ),
    );
  }
}

class _MetricItem {
  final IconData icon;
  final Color    color;
  final String   label, value;
  const _MetricItem({required this.icon, required this.color,
      required this.label, required this.value});
}

class _MetricCard extends StatelessWidget {
  final SkinConfig skin;
  final _MetricItem item;
  const _MetricCard({required this.skin, required this.item});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: skin.backgroundCard,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: item.color.withValues(alpha: 0.2)),
    ),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(item.icon, color: item.color, size: 22),
      const SizedBox(height: 6),
      Text(item.value, style: TextStyle(color: skin.textPrimary,
          fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 2),
      Text(item.label, style: TextStyle(
          color: skin.textMuted, fontSize: 9, letterSpacing: 1)),
    ]),
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

    return Container(
      height: 180,
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
                showTitles: true, reservedSize: 42,
                interval: 60,
                getTitlesWidget: (v, _) => Text(
                  _fmtPace(v),
                  style: TextStyle(color: skin.textMuted, fontSize: 9),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true, reservedSize: 20,
                getTitlesWidget: (v, _) {
                  final idx = v.round();
                  if (idx < 0 || idx >= splits.length) return const SizedBox.shrink();
                  return Text('K${splits[idx].km}',
                    style: TextStyle(color: skin.textMuted, fontSize: 9));
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
                final hr   = s.hrAvg > 0 ? '\n♥ ${s.hrAvg}bpm' : '';
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
            _SplitCell('KM',     flex: 1, color: skin.textMuted, header: true),
            _SplitCell('RITMO',  flex: 3, color: skin.textMuted, header: true),
            _SplitCell('FC',     flex: 2, color: skin.textMuted, header: true, alignRight: true),
          ]),
        ),
        Divider(color: skin.border, height: 1),
        // Filas
        ...splits.map((s) {
          final isBest = s.km == best;
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(children: [
              _SplitCell('${s.km}',        flex: 1, color: skin.textMuted),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(fmtPace(s.paceSec),
                    style: TextStyle(
                      color: isBest ? const Color(0xFF4CAF50) : skin.textPrimary,
                      fontSize: 14, fontWeight: FontWeight.w700,
                    )),
                  if (isBest) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('BEST', style: TextStyle(
                          color: Color(0xFF4CAF50), fontSize: 9, fontWeight: FontWeight.w800)),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    s.hrAvg > 0 ? '${s.hrAvg}bpm' : '--',
                    style: TextStyle(color: skin.textSecondary, fontSize: 12),
                  ),
                ],
              ).expand(),
            ]),
          );
        }),
        const SizedBox(height: 4),
      ]),
    );
  }
}

extension on Widget {
  Widget expand() => Expanded(child: this);
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
      style: TextStyle(
        color: color,
        fontSize: header ? 9 : 13,
        fontWeight: header ? FontWeight.w600 : FontWeight.w400,
        letterSpacing: header ? 1 : 0,
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
        label: '+${gainM.round()}m',
        icon: Icons.trending_up,
        color: const Color(0xFF66BB6A),
        skin: skin,
      ),
      if (lossM > 0) _Chip(
        label: '-${lossM.round()}m',
        icon: Icons.trending_down,
        color: const Color(0xFFEF5350),
        skin: skin,
      ),
      if (fastestKm != null) _Chip(
        label: '⚡ Mejor km $fastestKm',
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
      Icon(icon, color: color, size: 14),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(
          color: color, fontSize: 12, fontWeight: FontWeight.w600)),
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
  static const _zLabels = {
    'Z1': 'Recuperación  <60%',
    'Z2': 'Base aeróbica  60–70%',
    'Z3': 'Aeróbico mod.  70–80%',
    'Z4': 'Umbral láctico  80–90%',
    'Z5': 'VO₂max / Máx  >90%',
  };

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
                child: Container(color: _zColors[e.key] ?? Colors.grey),
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
          final clr  = _zColors[e.key] ?? Colors.grey;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Container(width: 10, height: 10,
                  decoration: BoxDecoration(color: clr, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(e.key, style: TextStyle(color: skin.textPrimary,
                          fontSize: 12, fontWeight: FontWeight.w700)),
                      Text('${min}min · $pct%', style: TextStyle(
                          color: skin.textMuted, fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(_zLabels[e.key] ?? '', style: TextStyle(
                      color: skin.textMuted, fontSize: 10)),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: sec / total,
                      backgroundColor: skin.border,
                      valueColor: AlwaysStoppedAnimation(clr),
                      minHeight: 4,
                    ),
                  ),
                ],
              )),
            ]),
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
            plan: '${planMin}min', real: realMin > 0 ? '${realMin}min' : '--',
            pct: durPct, color: _badge(durPct)),
        if (planDistM > 0) ...[
          Divider(color: skin.border, height: 20),
          _CompareRow(skin: skin, label: 'Distancia',
              plan: '${(planDistM / 1000).toStringAsFixed(1)}km',
              real: realDistM > 0 ? '${(realDistM / 1000).toStringAsFixed(2)}km' : '--',
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

  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: Text(label, style: TextStyle(color: skin.textMuted, fontSize: 12))),
    Text(plan, overflow: TextOverflow.ellipsis,
        style: TextStyle(color: skin.textMuted, fontSize: 13)),
    const SizedBox(width: 8),
    Icon(Icons.arrow_forward, color: skin.textMuted, size: 14),
    const SizedBox(width: 8),
    Text(real, overflow: TextOverflow.ellipsis,
        style: TextStyle(color: skin.textPrimary,
        fontSize: 13, fontWeight: FontWeight.w700)),
    const SizedBox(width: 8),
    if (pct > 0) Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('$pct%', style: TextStyle(
          color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    ),
  ]);
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
        child: Center(child: Text(trimp.round().toString(),
          style: TextStyle(color: _color, fontSize: 18, fontWeight: FontWeight.w800))),
      ),
      const SizedBox(width: 16),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('TRIMP — Carga $_level', style: TextStyle(
              color: skin.textPrimary, fontSize: 13, fontWeight: FontWeight.w700)),
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
      if (rpe > 0) Row(children: [
        _FeelingDot(label: 'RPE', value: '$rpe/10',
            sublabel: _rpeLabels[rpe] ?? '', color: _rpeColor(skin), skin: skin),
        if (energy != null) ...[
          const SizedBox(width: 12),
          _FeelingDot(label: 'ENERGÍA', value: '$energy/5',
              sublabel: energy! >= 4 ? 'Muy bien' : energy! >= 3 ? 'Regular' : 'Cansado',
              color: energy! >= 4 ? skin.success : energy! >= 3 ? skin.warning : skin.error,
              skin: skin),
        ],
      ]),
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
            Text('NOTAS DEL ATLETA', style: TextStyle(
                color: skin.textMuted, fontSize: 9, letterSpacing: 1.5)),
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
  final String label, value, sublabel;
  final Color  color;
  const _FeelingDot({required this.skin, required this.label,
      required this.value, required this.sublabel, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Column(children: [
      Text(label, style: TextStyle(color: skin.textMuted, fontSize: 9, letterSpacing: 1)),
      const SizedBox(height: 4),
      Text(value, style: TextStyle(
          color: color, fontSize: 20, fontWeight: FontWeight.w800)),
      const SizedBox(height: 2),
      Text(sublabel, style: TextStyle(color: skin.textMuted, fontSize: 10)),
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
class _SectionHeader extends StatelessWidget {
  final String     text;
  final SkinConfig skin;
  const _SectionHeader(this.text, this.skin);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 10),
    child: Text(text, style: TextStyle(
        color: skin.textMuted, fontSize: 10,
        letterSpacing: 2, fontWeight: FontWeight.w600)),
  );
}
