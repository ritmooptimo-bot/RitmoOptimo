// ============================================================
//  Lo que el deportista LEE en la tarjeta del bloque, antes de empezar.
//
//  ⚠️ La tarjeta enseñaba solo etiqueta, minutos y zona. En una sesión de series
//  se leía «Series 3 x 8 min · 27 min · R2» y ni una palabra de cuántas
//  repeticiones ni cuánto se recupera; en una de fuerza, «Fuerza general ·
//  25 min · R1» y ningún ejercicio. El dato venía del backend y no se pintaba.
// ============================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:ritmooptimo_mobile/core/session/resumen_bloque.dart';

void main() {
  group('series', () {
    test('dice cuántas, de cuánto y cuánto se recupera', () {
      final r = resumenSerieDe({
        'block': 'Series 3 x 8 min', 'min': 27, 'zone': 'R2',
        'reps': 3, 'rep_duration_min': 8, 'recovery_seconds': 90,
        'recovery_zone': 'R1',
      });
      expect(r, contains('3 ×'));
      expect(r, contains("8'"));
      expect(r, contains('recupera'));
      expect(r, contains("1' 30"));
    });

    test('series por distancia', () {
      final r = resumenSerieDe({'reps': 10, 'rep_distance_m': 400, 'recovery_seconds': 60});
      expect(r, contains('10 × 400 m'));
      expect(r, contains('1'));
    });

    test('AL REVÉS: un bloque continuo no inventa una serie', () {
      expect(resumenSerieDe({'block': 'Parte principal', 'min': 75, 'zone': 'R1'}), isNull);
    });

    test('AL REVÉS: media serie no se enseña', () {
      // reps sin duración: anunciar «6 series» sin decir de cuánto es peor que
      // no anunciar nada.
      expect(resumenSerieDe({'reps': 6, 'min': 20}), isNull);
    });

    test('una sola repetición no es una serie', () {
      expect(resumenSerieDe({'reps': 1, 'rep_duration_min': 8}), isNull);
    });
  });

  group('fuerza', () {
    final bloque = <String, dynamic>{
      'block': 'Fuerza general', 'min': 25, 'zone': 'R1',
      'tipo': 'circuito', 'rondas': 3, 'descanso_entre_rondas_s': 90,
      'ejercicios': [
        {'slug': 'sentadilla_goblet', 'nombre': 'Sentadilla goblet', 'series': 3,
         'reps': 10, 'carga': {'tipo': 'rir', 'valor': 4}, 'descanso_s': 60},
        {'slug': 'plancha_frontal', 'nombre': 'Plancha frontal', 'series': 3,
         'tiempo_s': 45, 'descanso_s': 45},
        {'slug': 'zancada_caminando', 'nombre': 'Zancada caminando', 'series': 3,
         'reps': 10, 'unilateral': true,
         'carga': {'tipo': 'kg', 'valor': 12}, 'descanso_s': 60},
      ],
    };

    test('una línea por ejercicio, con nombre de verdad', () {
      final l = lineasEjercicios(bloque);
      expect(l.length, 3);
      expect(l[0], startsWith('Sentadilla goblet'));
      expect(l.every((x) => !x.contains('_')), isTrue,
          reason: 'nadie entrena un slug: salió $l');
    });

    test('series y repeticiones, o segundos si va por tiempo', () {
      final l = lineasEjercicios(bloque);
      expect(l[0], contains('3×10'));
      expect(l[1], contains('3×45s'));
    });

    test('la carga SIEMPRE con su tipo', () {
      final l = lineasEjercicios(bloque);
      expect(l[0], contains('RIR 4'));
      expect(l[2], contains('12 kg'));
      expect(l[1], isNot(contains('RIR')),
          reason: 'en una plancha no hay repeticiones que reservarse');
    });

    test('el descanso y el "por lado"', () {
      final l = lineasEjercicios(bloque);
      expect(l[0], contains('desc 60s'));
      expect(l[2], contains('(por lado)'));
    });

    test('las rondas del circuito', () {
      expect(resumenRondas(bloque), '3 rondas · 90s entre rondas');
    });

    test('AL REVÉS: un bloque de carrera no lleva ejercicios ni rondas', () {
      final carrera = {'block': 'Parte principal', 'min': 75, 'zone': 'R1'};
      expect(lineasEjercicios(carrera), isEmpty);
      expect(resumenRondas(carrera), isNull);
    });

    test('sin nombre enriquecido, se cae al slug antes que dejarlo en blanco', () {
      final l = lineasEjercicios({'ejercicios': [
        {'slug': 'remo_mancuerna', 'series': 3, 'reps': 10}]});
      expect(l.single, startsWith('remo_mancuerna'));
    });
  });
}
