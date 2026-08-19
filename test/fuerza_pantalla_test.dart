// ============================================================
//  La sesión de fuerza tiene que ABRIR su pantalla.
//
//  ⚠️ EL FALLO: el endpoint devuelve `structure AS planned_structure`, y el
//  enrutado leía `session['structure']` — que NO EXISTE en la respuesta.
//  `desdeEstructura(null)` daba vacío, la pantalla de fuerza no se abría nunca,
//  y el deportista veía la de carrera con tres bloques («Calentamiento, Fuerza
//  general, Vuelta a la calma») en lugar de sus ejercicios.
//
//  Toda la pantalla —los pasos aplanados de un circuito, el descanso entre
//  series, el RIR al terminar— estaba escrita y no se había ejecutado jamás.
//
//  El payload de abajo es el que devuelve el backend de verdad.
// ============================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:ritmooptimo_mobile/models/ejercicio.dart';

void main() {
  // La sesión del sábado 22/08, tal como llega de `/athlete/session/:id`.
  final respuesta = <String, dynamic>{
    'id': 'x', 'session_type': 'fuerza', 'title': 'Fuerza general',
    'planned_structure': [
      {
        'block': 'Calentamiento', 'type': 'warmup', 'min': 10, 'zone': 'R1',
        'ejercicios': [
          {'slug': 'movilidad_cadera_90_90', 'nombre': 'Movilidad de cadera 90/90',
           'series': 2, 'tiempo_s': 45, 'descanso_s': 15},
          {'slug': 'movilidad_toracica', 'nombre': 'Movilidad torácica en el suelo',
           'series': 2, 'tiempo_s': 45, 'descanso_s': 15},
        ],
      },
      {
        'block': 'Fuerza general', 'type': 'strength', 'min': 25, 'zone': 'R1',
        'tipo': 'circuito', 'rondas': 3, 'descanso_entre_rondas_s': 90,
        'ejercicios': [
          {'slug': 'sentadilla_goblet', 'nombre': 'Sentadilla goblet', 'series': 3,
           'reps': 10, 'carga': {'tipo': 'rir', 'valor': 4}, 'descanso_s': 60},
          {'slug': 'peso_muerto_rumano', 'nombre': 'Peso muerto rumano', 'series': 3,
           'reps': 10, 'carga': {'tipo': 'rir', 'valor': 4}, 'descanso_s': 60,
           'pide_rir': true},
          {'slug': 'flexiones', 'nombre': 'Flexiones', 'series': 3, 'reps': 10,
           'carga': {'tipo': 'rir', 'valor': 4}, 'descanso_s': 60},
          {'slug': 'plancha_frontal', 'nombre': 'Plancha frontal', 'series': 3,
           'tiempo_s': 45, 'descanso_s': 45},
        ],
      },
      {
        'block': 'Vuelta a la calma', 'type': 'cooldown', 'min': 10, 'zone': 'R1',
        'ejercicios': [
          {'slug': 'estiramiento_gemelo', 'nombre': 'Estiramiento de gemelo y sóleo',
           'series': 2, 'tiempo_s': 30, 'descanso_s': 15},
        ],
      },
    ],
  };

  // Lo mismo que hace el enrutado de `session_screen.dart`.
  dynamic estructuraDe(Map<String, dynamic> s) =>
      s['planned_structure'] ?? s['structure'];

  test('la sesión de fuerza abre su pantalla', () {
    final bloques = BloqueFuerza.desdeEstructura(estructuraDe(respuesta));
    expect(bloques, isNotEmpty,
        reason: 'con `structure` a secas daba vacío y no se abría nunca');
    expect(bloques.length, 3);
  });

  test('AL REVÉS: leyendo `structure` (el fallo) no se abría', () {
    final bloques = BloqueFuerza.desdeEstructura(respuesta['structure']);
    expect(bloques, isEmpty,
        reason: 'esto reproduce el fallo: el campo no existe en la respuesta');
  });

  test('el circuito se aplana en el orden REAL en que se hace', () {
    final bloques = BloqueFuerza.desdeEstructura(estructuraDe(respuesta));
    final pasos = PasoSerie.desdeBloques(bloques);

    // Calentamiento 2×2 + circuito 3 rondas × 4 ejercicios + calma 1×2 = 18
    expect(pasos.length, 18, reason: 'salieron ${pasos.length}');

    // El circuito va ronda a ronda, no ejercicio a ejercicio.
    final circuito = pasos.where((p) => p.bloque == 'Fuerza general').toList();
    expect(circuito.length, 12);
    expect(circuito[0].ejercicio.nombre, 'Sentadilla goblet');
    expect(circuito[1].ejercicio.nombre, 'Peso muerto rumano');
    expect(circuito[4].ejercicio.nombre, 'Sentadilla goblet',
        reason: 'la ronda 2 vuelve a empezar por el primero');
    expect(circuito[4].ronda, 2);
  });

  test('cada paso sabe qué hacer: series, reps o tiempo, carga y descanso', () {
    final pasos = PasoSerie.desdeBloques(
        BloqueFuerza.desdeEstructura(estructuraDe(respuesta)));
    final sentadilla = pasos.firstWhere((p) => p.ejercicio.slug == 'sentadilla_goblet');

    expect(sentadilla.ejercicio.nombre, 'Sentadilla goblet',
        reason: 'nadie entrena un slug');
    expect(sentadilla.ejercicio.reps, 10);
    expect(sentadilla.ejercicio.cargaTipo, 'rir');
    expect(sentadilla.ejercicio.cargaValor, 4);
    expect(sentadilla.descansoS, 60);
    expect(sentadilla.deRondas, 3);
  });

  test('un ejercicio por tiempo va con segundos, no con repeticiones', () {
    final pasos = PasoSerie.desdeBloques(
        BloqueFuerza.desdeEstructura(estructuraDe(respuesta)));
    final plancha = pasos.firstWhere((p) => p.ejercicio.slug == 'plancha_frontal');
    expect(plancha.ejercicio.tiempoS, 45);
    expect(plancha.ejercicio.reps, isNull);
    expect(plancha.ejercicio.cargaTipo, isNull,
        reason: 'en una plancha no hay repeticiones que reservarse');
  });

  test('AL REVÉS: una sesión de carrera NO abre la pantalla de fuerza', () {
    final carrera = {
      'planned_structure': [
        {'block': 'Calentamiento', 'type': 'warmup', 'min': 15, 'zone': 'R1'},
        {'block': 'Series 3 x 8 min', 'type': 'intervals', 'min': 27, 'zone': 'R2',
         'reps': 3, 'rep_duration_min': 8, 'recovery_seconds': 90},
      ],
    };
    expect(BloqueFuerza.desdeEstructura(estructuraDe(carrera)), isEmpty);
  });
}
