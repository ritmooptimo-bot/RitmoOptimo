/// Un ejercicio de una sesión de fuerza, tal y como viaja en `structure`.
///
/// ⚠️ DE DÓNDE VIENE. Hasta el 11/08/2026 una sesión de fuerza llegaba así:
///
///     { "block": "Fuerza tren superior", "min": 20,
///       "descripcion": "3 rondas de press de hombros, remo con banda y
///                       flexiones, con descansos de 60-90 segundos." }
///
/// Todo el entrenamiento dentro de una frase. La app solo podía enseñar el
/// párrafo y un cronómetro: no sabía cuántos ejercicios había, ni las
/// repeticiones, ni por cuál iba el deportista.
class Ejercicio {
  final String slug;
  final String nombre;      // el legible; si no viene, se usa el slug
  final int    series;

  /// Repeticiones **o** segundos: uno de los dos, nunca ninguno.
  /// En un isométrico (plancha, sentadilla en pared) no hay repeticiones.
  final int?   reps;
  final int?   tiempoS;

  final int    descansoS;

  /// ⚠️ La carga SIEMPRE con su tipo. Un 20 en kilos y un 2 de RIR no son la
  /// misma escala, y sin decir cuál es no se puede ni enseñar ni comparar. Es la
  /// mina que ya costó dos veces en el backend (bienestar y carga de sesión).
  final String? cargaTipo;   // kg · rir · rpe · %1rm · banda · peso_corporal
  final dynamic cargaValor;

  final String? nota;
  final bool    unilateral;

  /// ⚠️ ¿Hay que preguntarle cuánto le sobraba al terminar?
  ///
  /// Solo en los ejercicios con e1RM. El RIR que guardábamos era el PRESCRITO
  /// —le pedimos 2 y anotábamos 2— y estimar el máximo con eso es calcular sobre
  /// un número que nadie ha medido. Preguntarlo en los diez ejercicios de la
  /// sesión sería un interrogatorio y dejaría de contestarse; en dos, se hace.
  final bool    pideRir;

  const Ejercicio({
    required this.slug,
    required this.nombre,
    required this.series,
    this.reps,
    this.tiempoS,
    this.descansoS = 60,
    this.cargaTipo,
    this.cargaValor,
    this.nota,
    this.unilateral = false,
    this.pideRir = false,
  });

  static int? _int(dynamic v) =>
      v == null ? null : (v is int ? v : int.tryParse(v.toString()));

  factory Ejercicio.fromJson(Map<String, dynamic> j) {
    final carga = j['carga'];
    return Ejercicio(
      slug:   (j['slug'] ?? '').toString(),
      nombre: (j['nombre'] ?? j['name'] ?? j['slug'] ?? '').toString(),
      series: _int(j['series']) ?? 1,
      reps:   _int(j['reps']),
      tiempoS: _int(j['tiempo_s'] ?? j['tiempoS']),
      descansoS: _int(j['descanso_s'] ?? j['descansoS']) ?? 60,
      cargaTipo:  carga is Map ? carga['tipo']?.toString() : null,
      cargaValor: carga is Map ? carga['valor'] : null,
      nota: (j['nota'] ?? j['indicaciones'])?.toString(),
      unilateral: j['unilateral'] == true,
      pideRir: j['pide_rir'] == true,
    );
  }

  /// "10 reps" · "10 reps por lado" · "40 s"
  String get objetivo {
    if (tiempoS != null) return '$tiempoS s';
    if (reps != null) return unilateral ? '$reps reps por lado' : '$reps reps';
    return '—';
  }

  /// "RIR 2" · "20 kg" · null si va con el propio peso.
  String? get carga {
    if (cargaTipo == null || cargaTipo == 'peso_corporal') return null;
    switch (cargaTipo) {
      case 'kg':    return '$cargaValor kg';
      case 'rir':   return 'RIR $cargaValor';
      case 'rpe':   return 'RPE $cargaValor/10';
      case '%1rm':  return '$cargaValor % 1RM';
      case 'banda': return 'banda $cargaValor';
      default:      return '$cargaValor';
    }
  }
}

/// Un bloque con ejercicios: el "subbloque" de la sesión.
class BloqueFuerza {
  final String nombre;
  final String? tipo;        // series · circuito · superserie · emom · amrap
  final int rondas;
  final int descansoEntreRondasS;
  final String? descripcion;
  final List<Ejercicio> ejercicios;

  const BloqueFuerza({
    required this.nombre,
    required this.ejercicios,
    this.tipo,
    this.rondas = 1,
    this.descansoEntreRondasS = 90,
    this.descripcion,
  });

  bool get esCircuito => tipo == 'circuito' || tipo == 'emom' || tipo == 'amrap';

  factory BloqueFuerza.fromJson(Map<String, dynamic> j) {
    final raw = j['ejercicios'];
    return BloqueFuerza(
      nombre: (j['block'] ?? j['bloque'] ?? 'Bloque').toString(),
      tipo: j['tipo']?.toString(),
      rondas: Ejercicio._int(j['rondas']) ?? 1,
      descansoEntreRondasS: Ejercicio._int(j['descanso_entre_rondas_s']) ?? 90,
      descripcion: j['descripcion']?.toString(),
      ejercicios: raw is List
          ? raw
              .whereType<Map>()
              .map((e) => Ejercicio.fromJson(Map<String, dynamic>.from(e)))
              .where((e) => e.slug.isNotEmpty)
              .toList()
          : const [],
    );
  }

  /// Los bloques CON ejercicios de una `structure`.
  ///
  /// Devuelve vacío en una sesión de carrera: es lo que usa la app para decidir
  /// si guía por ejercicios o por tiempo, sin preguntarle el tipo a nadie.
  static List<BloqueFuerza> desdeEstructura(dynamic structure) {
    if (structure is! List) return const [];
    return structure
        .whereType<Map>()
        .map((b) => BloqueFuerza.fromJson(Map<String, dynamic>.from(b)))
        .where((b) => b.ejercicios.isNotEmpty)
        .toList();
  }
}

/// Una serie concreta dentro de la sesión: el paso que la app va guiando.
///
/// Se aplana a propósito: un circuito de 3 rondas × 5 ejercicios son 15 pasos
/// en el orden REAL en que se hacen. Con la lista ya plana, avanzar es sumar
/// uno — y no hay que reconstruir "por dónde iba" con tres contadores anidados,
/// que es donde aparecen los fallos de fuera-por-uno.
class PasoSerie {
  final Ejercicio ejercicio;
  final int serie;        // 1-based, dentro de su ejercicio
  final int deSeries;
  final int ronda;        // 1-based; 1 si no es circuito
  final int deRondas;
  final String bloque;
  final int descansoS;

  const PasoSerie({
    required this.ejercicio,
    required this.serie,
    required this.deSeries,
    required this.ronda,
    required this.deRondas,
    required this.bloque,
    required this.descansoS,
  });

  static List<PasoSerie> desdeBloques(List<BloqueFuerza> bloques) {
    final pasos = <PasoSerie>[];
    for (final b in bloques) {
      if (b.esCircuito) {
        // Circuito: una ronda de TODOS los ejercicios, y vuelta a empezar.
        for (var r = 1; r <= b.rondas; r++) {
          for (final e in b.ejercicios) {
            pasos.add(PasoSerie(
              ejercicio: e, serie: r, deSeries: b.rondas,
              ronda: r, deRondas: b.rondas, bloque: b.nombre,
              // Tras el último de la ronda se descansa lo de la ronda, que es
              // más largo: es el descanso que de verdad toca ahí.
              descansoS: e == b.ejercicios.last ? b.descansoEntreRondasS : e.descansoS,
            ));
          }
        }
      } else {
        // Por series: todas las de un ejercicio y se pasa al siguiente.
        for (final e in b.ejercicios) {
          for (var s = 1; s <= e.series; s++) {
            pasos.add(PasoSerie(
              ejercicio: e, serie: s, deSeries: e.series,
              ronda: 1, deRondas: 1, bloque: b.nombre,
              descansoS: e.descansoS,
            ));
          }
        }
      }
    }
    return pasos;
  }
}
