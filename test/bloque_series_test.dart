// ============================================================
//  La app tiene que RECONOCER una serie para poder guiarla.
//
//  ⚠️ Aquí estaba el fallo silencioso: `typeRaw` se sacaba de
//  `b['block'] ?? … ?? b['type']`, o sea el NOMBRE humano primero. Un bloque
//  llamado "Series 4 x 6 min" no coincidía exactamente con 'series', así que
//  `isInterval` daba false y toda la guía de repeticiones —cuenta atrás,
//  pitidos, "serie 3 de 6"— llevaba meses escrita sin dispararse jamás.
//
//  Los bloques de estos tests son los que produce el backend de verdad.
// ============================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:ritmooptimo_mobile/core/audio/session_audio_controller.dart';

void main() {
  // El bloque tal cual lo escribe ahora el generador.
  final serieReal = <String, dynamic>{
    'block': 'Series 4 x 6 min',
    'type': 'intervals',
    'min': 30,
    'zone': 'R2',
    'zone_escala': 'percepcion',
    'reps': 4,
    'rep_duration_min': 6,
    'recovery_seconds': 120,
    'recovery_zone': 'R1',
    'target_pace': '4:30',
  };

  test('un bloque de series se reconoce como serie', () {
    final b = BlockInfo.fromMap(0, serieReal);
    expect(b.isInterval, isTrue,
        reason: 'con el orden viejo el nombre "Series 4 x 6 min" no casaba y daba false');
    expect(b.repCount, 4);
    expect(b.repDurationSeconds, 360);
    expect(b.recoverySeconds, 120);
  });

  test('la etiqueta que se LEE es el nombre del entrenador, no "Intervalos"', () {
    final b = BlockInfo.fromMap(0, serieReal);
    expect(b.label, 'Series 4 x 6 min');
  });

  test('el tipo canónico gana al nombre humano', () {
    // "Parte principal" no dice nada; `type` sí.
    final b = BlockInfo.fromMap(0, {
      'block': 'Parte principal', 'type': 'intervals', 'min': 20, 'zone': 'R3',
      'reps': 6, 'rep_duration_min': 2, 'recovery_seconds': 90,
    });
    expect(b.isInterval, isTrue);
    expect(b.repCount, 6);
  });

  test('si TRAE repeticiones es una serie, diga lo que diga la etiqueta', () {
    final b = BlockInfo.fromMap(0, {
      'block': 'Cambios de ritmo', 'type': 'lo_que_sea', 'min': 20, 'zone': 'R2',
      'reps': 5, 'rep_duration_min': 3, 'recovery_seconds': 60,
    });
    expect(b.isInterval, isTrue, reason: 'el dato es la prueba');
    expect(b.repCount, 5);
  });

  test('AL REVÉS: un rodaje continuo NO se trata como serie', () {
    final b = BlockInfo.fromMap(0, {
      'block': 'Parte principal', 'type': 'continuous', 'min': 75, 'zone': 'R1',
    });
    expect(b.isInterval, isFalse);
    expect(b.repCount, isNull);
  });

  test('AL REVÉS: media serie no se guía como serie', () {
    // reps sin duración de repetición: la app no sabría cronometrar nada.
    final b = BlockInfo.fromMap(0, {
      'block': 'Series', 'type': 'continuous', 'min': 20, 'zone': 'R2', 'reps': 6,
    });
    expect(b.isInterval, isFalse,
        reason: 'anunciar 6 series que no sabe cronometrar es peor que no anunciarlas');
  });

  test('el calentamiento sigue siendo calentamiento', () {
    final b = BlockInfo.fromMap(0, {
      'block': 'Calentamiento', 'type': 'warmup', 'min': 15, 'zone': 'R1',
    });
    expect(b.isInterval, isFalse);
    expect(b.label, 'Calentamiento');
  });
}
