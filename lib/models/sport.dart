import 'package:flutter/material.dart';

/// El DEPORTE de una sesión — y todo lo que cambia con él.
///
/// Hasta ahora la app medía todo como si fuera carrera a pie: mostraba "RITMO /km"
/// en una salida en bici (donde nadie mira min/km, se mira km/h) y "DIST km" en
/// una sesión de fuerza (donde no hay distancia que valga). Con triatletas en la
/// base — que nadan, pedalean y corren la misma semana — eso no se sostiene.
///
/// Esta clase es el ÚNICO sitio donde se decide qué significa cada deporte. Si
/// mañana se añade uno nuevo, se toca aquí y el resto de la app se entera sola.
enum Sport {
  running,
  trail,
  ciclismo,
  natacion,
  fuerza,
  otro;

  /// El valor tal cual lo manda el backend (columna `sport` de training_sessions).
  /// Tolerante a mayúsculas, acentos y a los nombres en inglés del GPS.
  static Sport fromApi(String? raw) {
    switch ((raw ?? '').toLowerCase().trim()) {
      case 'running':
      case 'carrera':
        return Sport.running;
      case 'trail':
        return Sport.trail;
      case 'ciclismo':
      case 'cycling':
      case 'bici':
        return Sport.ciclismo;
      case 'natacion':
      case 'natación':
      case 'swimming':
        return Sport.natacion;
      case 'fuerza':
      case 'strength':
      case 'gym':
        return Sport.fuerza;
      case 'otro':
      case 'other':
        return Sport.otro;
      default:
        // Un deporte desconocido se trata como carrera: es lo que hacía la app
        // entera hasta ahora, así que no rompe nada existente.
        return Sport.running;
    }
  }

  String get api => name; // running | trail | ciclismo | natacion | fuerza | otro

  String get label => switch (this) {
        Sport.running  => 'Carrera',
        Sport.trail    => 'Trail',
        Sport.ciclismo => 'Ciclismo',
        Sport.natacion => 'Natación',
        Sport.fuerza   => 'Fuerza',
        Sport.otro     => 'Caminata',
      };

  IconData get icon => switch (this) {
        Sport.running  => Icons.directions_run,
        Sport.trail    => Icons.terrain,
        Sport.ciclismo => Icons.directions_bike,
        Sport.natacion => Icons.pool,
        Sport.fuerza   => Icons.fitness_center,
        Sport.otro     => Icons.directions_walk,
      };

  /// ¿Tiene sentido grabar recorrido? En un gimnasio no, y en una piscina el GPS
  /// solo pinta un garabato de ruido (ver [askPoolOrOpenWater]).
  bool get usesGps => switch (this) {
        Sport.running || Sport.trail || Sport.ciclismo => true,
        Sport.natacion => true, // solo si el atleta dice "aguas abiertas"
        Sport.otro => true,     // una caminata también deja recorrido
        Sport.fuerza => false,
      };

  /// En natación hay que preguntar: en piscina el GPS estorba, en aguas abiertas
  /// es justo lo que se quiere.
  bool get askPoolOrOpenWater => this == Sport.natacion;

  /// ¿Se mide distancia? En fuerza no existe tal cosa.
  bool get hasDistance => this != Sport.fuerza;

  /// Cómo se expresa la intensidad de este deporte.
  SpeedMode get speedMode => switch (this) {
        Sport.running || Sport.trail => SpeedMode.pacePerKm,     // 4:30 /km
        Sport.ciclismo               => SpeedMode.speedKmh,      // 28,4 km/h
        Sport.natacion               => SpeedMode.pacePer100m,   // 1:52 /100m
        Sport.otro                   => SpeedMode.pacePerKm,     // caminata
        Sport.fuerza                 => SpeedMode.none,
      };

  /// El `sport_type` que espera el backend en el track GPS (athlete_gps_tracks).
  String get gpsSportType => switch (this) {
        Sport.running  => 'running',
        Sport.trail    => 'trail',
        Sport.ciclismo => 'cycling',
        Sport.natacion => 'swimming',
        Sport.fuerza   => 'strength',
        Sport.otro     => 'other',
      };

  // ── Formateo de las métricas en vivo ──────────────────────────────────

  /// Etiqueta corta de la métrica de velocidad, para la cabecera.
  String get speedLabel => switch (speedMode) {
        SpeedMode.pacePerKm   => 'RITMO',
        SpeedMode.pacePer100m => 'RITMO',
        SpeedMode.speedKmh    => 'VEL',
        SpeedMode.none        => '',
      };

  String get speedUnit => switch (speedMode) {
        SpeedMode.pacePerKm   => '/km',
        SpeedMode.pacePer100m => '/100m',
        SpeedMode.speedKmh    => 'km/h',
        SpeedMode.none        => '',
      };

  /// Convierte el ritmo en segundos/km que calcula el GPS a lo que toca mostrar.
  /// `secPerKm` nulo o 0 (parado, sin señal) devuelve el guion correspondiente.
  String formatSpeed(double? secPerKm) {
    if (secPerKm == null || secPerKm <= 0 || secPerKm.isInfinite || secPerKm.isNaN) {
      return speedMode == SpeedMode.speedKmh ? '--' : '--:--';
    }
    switch (speedMode) {
      case SpeedMode.pacePerKm:
        return _mmss(secPerKm);
      case SpeedMode.pacePer100m:
        return _mmss(secPerKm / 10); // 1 km = 10 × 100 m
      case SpeedMode.speedKmh:
        return (3600 / secPerKm).toStringAsFixed(1).replaceAll('.', ',');
      case SpeedMode.none:
        return '--';
    }
  }

  String get distanceLabel => 'DIST';

  String get distanceUnit => this == Sport.natacion ? 'm' : 'km';

  /// La natación se cuenta en metros (1.500 m, no 1,50 km).
  String formatDistance(double metros) {
    if (this == Sport.natacion) return metros.round().toString();
    return (metros / 1000).toStringAsFixed(2).replaceAll('.', ',');
  }

  static String _mmss(double segundos) {
    final m = segundos ~/ 60;
    final s = (segundos % 60).round();
    // 4:60 no existe: el redondeo puede empujar a 60 s
    if (s == 60) return '${m + 1}:00';
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// Lo que se ofrece para un entrenamiento libre: las cinco especialidades de la
  /// casa más la caminata. No abrimos el catálogo entero — 'otro' es la caminata
  /// o la marcha, que comparte métricas con la carrera (ritmo, distancia, mapa)
  /// pero NO es correr: mezclarlas falsearía su ritmo medio y lo que le diga el
  /// agente ("hiciste una carrera a 11:30/km" cuando fue un paseo).
  static const List<Sport> especialidades = [
    Sport.running,
    Sport.trail,
    Sport.ciclismo,
    Sport.fuerza,
    Sport.natacion,
    Sport.otro,
  ];
}

enum SpeedMode { pacePerKm, pacePer100m, speedKmh, none }
