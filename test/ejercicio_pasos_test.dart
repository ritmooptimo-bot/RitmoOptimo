import 'package:flutter_test/flutter_test.dart';
import 'package:ritmooptimo_mobile/models/ejercicio.dart';

/// El aplanado es donde se esconden los fallos de fuera-por-uno: un circuito de
/// 3 rondas × 5 ejercicios son 15 pasos, y en el ORDEN en que se hacen de verdad.
void main() {
  final circuito = [
    {'block': 'Fuerza general', 'tipo': 'circuito', 'rondas': 3,
     'descanso_entre_rondas_s': 90,
     'ejercicios': [
       {'slug': 'sentadilla_goblet', 'series': 3, 'reps': 10,
        'carga': {'tipo': 'rir', 'valor': 2}, 'descanso_s': 45},
       {'slug': 'plancha_lateral', 'series': 3, 'tiempo_s': 40, 'descanso_s': 45},
     ]},
  ];

  test('una sesión de carrera no tiene bloques de fuerza', () {
    expect(BloqueFuerza.desdeEstructura([
      {'block': 'Rodaje', 'min': 40, 'zone': 'R1'}
    ]), isEmpty);
  });

  test('circuito: rondas × ejercicios, en el orden real', () {
    final pasos = PasoSerie.desdeBloques(BloqueFuerza.desdeEstructura(circuito));
    expect(pasos.length, 6); // 3 rondas × 2 ejercicios
    // Ronda 1: los dos ejercicios; ronda 2: otra vez los dos…
    expect(pasos[0].ejercicio.slug, 'sentadilla_goblet');
    expect(pasos[1].ejercicio.slug, 'plancha_lateral');
    expect(pasos[2].ejercicio.slug, 'sentadilla_goblet');
    expect(pasos[2].ronda, 2);
    expect(pasos.last.ronda, 3);
  });

  test('tras el último de la ronda, el descanso es el LARGO', () {
    final pasos = PasoSerie.desdeBloques(BloqueFuerza.desdeEstructura(circuito));
    expect(pasos[0].descansoS, 45);  // entre ejercicios
    expect(pasos[1].descansoS, 90);  // fin de ronda
  });

  test('por series: todas las de un ejercicio antes de pasar al siguiente', () {
    final pasos = PasoSerie.desdeBloques(BloqueFuerza.desdeEstructura([
      {'block': 'Fuerza', 'tipo': 'series', 'ejercicios': [
        {'slug': 'a', 'series': 3, 'reps': 10},
        {'slug': 'b', 'series': 2, 'reps': 8},
      ]},
    ]));
    expect(pasos.map((p) => p.ejercicio.slug).toList(), ['a','a','a','b','b']);
    expect(pasos[2].serie, 3);
    expect(pasos[3].serie, 1);
  });

  test('la carga se lee con su unidad, nunca un número suelto', () {
    final e = Ejercicio.fromJson({'slug':'x','series':3,'reps':10,
      'carga':{'tipo':'rir','valor':2}});
    expect(e.carga, 'RIR 2');
    expect(Ejercicio.fromJson({'slug':'x','series':3,'reps':10,
      'carga':{'tipo':'kg','valor':22}}).carga, '22 kg');
    // Peso corporal: no se enseña carga, que sería ruido.
    expect(Ejercicio.fromJson({'slug':'x','series':3,'reps':10,
      'carga':{'tipo':'peso_corporal'}}).carga, isNull);
    expect(Ejercicio.fromJson({'slug':'x','series':3,'reps':10}).carga, isNull);
  });

  test('isométrico: se mide en segundos, no en repeticiones', () {
    final e = Ejercicio.fromJson({'slug':'plancha','series':3,'tiempo_s':40});
    expect(e.objetivo, '40 s');
    expect(e.reps, isNull);
  });

  test('unilateral: las reps son POR LADO y se dice', () {
    final e = Ejercicio.fromJson({'slug':'bulgara','series':3,'reps':8,'unilateral':true});
    expect(e.objetivo, '8 reps por lado');
  });

  test('un ejercicio sin slug se descarta, no rompe la pantalla', () {
    final b = BloqueFuerza.desdeEstructura([
      {'block':'F','ejercicios':[{'series':3,'reps':10},{'slug':'ok','series':3,'reps':10}]}
    ]);
    expect(b.first.ejercicios.length, 1);
  });
}
