// Comprueba, EJECUTANDO el controlador, las dos cosas que pidió el usuario:
//  1. Que se anuncian TODOS los bloques, no solo el 1 y el 2 (el fallo del 04/08:
//     tras los pitidos del bloque 2 la fase blockBeeps era un callejón sin salida
//     y ya no volvía a hablar ni para el bloque 3 ni para cerrar la sesión).
//  2. Que cada kilómetro se dice el ritmo del último km.
//
// No toca audio real: se sustituye AudioCueService por un doble que apunta lo
// que se habría dicho.

import 'package:flutter_test/flutter_test.dart';
import 'package:ritmooptimo_mobile/core/audio/audio_cue_service.dart';
import 'package:ritmooptimo_mobile/core/audio/session_audio_controller.dart';

/// Doble de prueba: en vez de hablar, apunta.
class AudioEspia implements AudioCueService {
  final List<String> dicho = [];
  final List<String> pitidos = [];

  @override
  Future<void> speak(String text) async => dicho.add(text);
  @override
  Future<void> beepShort() async => pitidos.add('corto');
  @override
  Future<void> beepLong() async => pitidos.add('largo');
  @override
  Future<void> countdown5() async => pitidos.add('cuenta-5');
  @override
  Future<void> init() async {}
  @override
  Future<void> startSession() async {}
  @override
  Future<void> stopSession() async {}
  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation i) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('anuncia TODOS los bloques y el ritmo de cada kilómetro', () async {
    final espia = AudioEspia();

    // 4 bloques de 3 minutos: calentamiento, rodaje, progresión, enfriamiento.
    // Tres minutos por bloque para que, a ritmo realista, dé tiempo a cruzar
    // dos kilómetros dentro de la sesión.
    const minPorBloque = 3;
    final controlador = SessionAudioController(
      audio: espia,
      rawBlocks: [
        {'block': 'warmup',   'min': minPorBloque, 'descripcion': 'Calentamiento suave'},
        {'block': 'steady',   'min': minPorBloque, 'descripcion': 'Rodaje',     'ritmo_objetivo': '5:30'},
        {'block': 'steady',   'min': minPorBloque, 'descripcion': 'Progresión', 'ritmo_objetivo': '5:00'},
        {'block': 'cooldown', 'min': minPorBloque, 'descripcion': 'Enfriamiento'},
      ],
    );

    await controlador.onSessionStart();

    // 10 s de cuenta atrás + 4 bloques + margen. Corre a 3,33 m/s (12 km/h =
    // 5:00/km): en los 12 minutos de sesión recorre ~2,4 km, así que tienen
    // que sonar los avisos del km 1 y del km 2.
    const totalSeg = 10 + 4 * minPorBloque * 60 + 20;
    for (int t = 0; t <= totalSeg; t++) {
      final metros = t <= 10 ? 0 : ((t - 10) * 3.33).round();
      controlador.onTick(t, distanceM: metros);
      // Dejar correr el async del controlador (incluidas sus pausas de 1,8 s
      // entre bloques). Sin esto los ticks se solapan y no se ve nada.
      await Future.delayed(const Duration(milliseconds: 12));
    }
    // Margen final para que termine la última transición
    await Future.delayed(const Duration(milliseconds: 2500));

    // ── Qué se dijo ──────────────────────────────────────────────────
    // ignore: avoid_print
    print('\n─── LO QUE SE HABRÍA OÍDO ───');
    for (final f in espia.dicho) {
      // ignore: avoid_print
      print('  🔊 $f');
    }

    final todo = espia.dicho.join(' | ');

    // 1. Los CUATRO bloques se anuncian
    for (final n in [1, 2, 3, 4]) {
      expect(todo, contains('Bloque $n,'),
          reason: 'No se anunció el comienzo del bloque $n');
    }
    // 2. Y los cuatro se dan por completados
    for (final n in [1, 2, 3, 4]) {
      expect(todo, contains('Bloque $n completado'),
          reason: 'No se anunció el fin del bloque $n');
    }
    // 3. La sesión se cierra hablando (antes se quedaba muda)
    expect(todo, contains('Sesión completada'),
        reason: 'La sesión terminó sin decir nada');

    // 4. Aviso por kilómetro con el ritmo (km 1 y km 2)
    expect(todo, contains('Kilómetro 1'), reason: 'No avisó del km 1');
    expect(todo, contains('Kilómetro 2'), reason: 'No avisó del km 2');
    expect(todo, contains('Ritmo:'),      reason: 'No dijo el ritmo del km');
    // Y el ritmo anunciado tiene que parecerse al real (3,33 m/s ≈ 5:00/km)
    final km1 = espia.dicho.firstWhere((f) => f.contains('Kilómetro 1'));
    expect(RegExp(r'Ritmo: (\d):(\d\d)').firstMatch(km1)?.group(1), '5',
        reason: 'El ritmo anunciado no cuadra con la velocidad simulada: $km1');
  });
}
