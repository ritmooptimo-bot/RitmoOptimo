// ============================================================
//  Lo que el ENTRENADOR va a ver de cada serie.
//
//  La pregunta que hay que contestar es «¿se está cumpliendo el objetivo de la
//  serie?», y eso no se responde con la media del bloque: se puede hacer la
//  primera clavada y hundirse en las dos últimas, y la media sale igual de
//  bonita que si se hubieran bordado las tres.
//
//  ⚠️ Antes, cada repetición se medía, se decía en voz alta («serie 2
//  completada, ritmo 4:35») y SE TIRABA: era una clase privada que no salía del
//  controlador. Al entrenador le llegaba solo el agregado del bloque.
// ============================================================
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ritmooptimo_mobile/core/audio/salida_de_audio.dart';
import 'package:ritmooptimo_mobile/core/audio/session_audio_controller.dart';

class AudioMudo implements SalidaDeAudio {
  @override Future<void> startSession() async {}
  @override Future<void> stopSession() async {}
  @override Future<void> speak(String t) async {}
  @override Future<void> beepShort() async {}
  @override Future<void> beepLong() async {}
  @override Future<void> countdown5() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final bloques = <Map<String, dynamic>>[
    {'block': 'Calentamiento', 'type': 'warmup', 'min': 1, 'zone': 'R1'},
    {
      'block': 'Series 3 x 8 min', 'type': 'intervals', 'min': 27, 'zone': 'R2',
      'reps': 3, 'rep_duration_min': 8, 'recovery_seconds': 90,
      'recovery_zone': 'R1', 'target_pace': '4:30',
    },
    {'block': 'Vuelta a la calma', 'type': 'cooldown', 'min': 1, 'zone': 'R1'},
  ];

  /// Corre la sesión con una FC que SUBE serie a serie (155, 165, 175), que es
  /// justo la deriva que un entrenador quiere poder ver.
  List<Map<String, dynamic>> correr() {
    late List<Map<String, dynamic>> json;
    fakeAsync((async) {
      final c = SessionAudioController(audio: AudioMudo(), rawBlocks: bloques);
      c.onSessionStart();
      async.flushMicrotasks();

      for (var t = 0; t <= 2200; t++) {
        // El pulso sube con el tiempo: 150 al principio, ~180 al final.
        final hr = 150 + (t ~/ 70);
        c.onTick(t, distanceM: t * 3, hr: hr);
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
      }
      json = c.resultadosDeBloques.map((b) => b.toJson()).toList();
    });
    return json;
  }

  test('cada serie llega al entrenador con su tiempo, ritmo y pulso', () {
    final bloquesJson = correr();
    final serie = bloquesJson.firstWhere((b) => b['repeticiones'] != null);
    final reps = (serie['repeticiones'] as List).cast<Map<String, dynamic>>();

    expect(reps.length, 3, reason: 'tres series, tres registros');
    for (var i = 0; i < reps.length; i++) {
      final r = reps[i];
      expect(r['n'], i + 1);
      expect(r['de'], 3);
      expect(r['seg_previstos'], 480, reason: 'lo que pedía el plan');
      expect(r['seg_reales'], closeTo(480, 3), reason: 'lo que duró de verdad');
      expect(r['pace_sec_km'], isNotNull, reason: 'sin ritmo no se juzga una serie');
      expect(r['hr_avg'], isNotNull, reason: 'SIN PULSO no se sabe si la dosis fue la buena');
      expect(r['hr_max'], isNotNull);
    }
  });

  test('el pulso es el DE CADA serie, no el del bloque entero', () {
    final bloquesJson = correr();
    final reps = ((bloquesJson.firstWhere((b) => b['repeticiones'] != null)
        )['repeticiones'] as List).cast<Map<String, dynamic>>();

    final fc = reps.map((r) => r['hr_avg'] as int).toList();
    // La FC sube a lo largo de la sesión: si cada serie midiera el bloque
    // entero, las tres darían lo mismo. Eso es justo lo que se quiere ver.
    expect(fc[0], lessThan(fc[1]), reason: 'serie 1 $fc[0] vs serie 2 ${fc[1]}');
    expect(fc[1], lessThan(fc[2]), reason: 'la deriva tiene que verse');
    expect(fc.toSet().length, 3, reason: 'tres valores distintos, no la misma media repetida');
  });

  test('un bloque que NO es de series no lleva repeticiones', () {
    final bloquesJson = correr();
    final calentamiento = bloquesJson.first;
    expect(calentamiento.containsKey('repeticiones'), isFalse,
        reason: 'un calentamiento no tiene series que enumerar');
  });

  test('el bloque sigue llevando su propio resumen', () {
    final bloquesJson = correr();
    final serie = bloquesJson.firstWhere((b) => b['repeticiones'] != null);
    expect(serie['hr_avg'], isNotNull);
    expect(serie['min'], isNotNull);
    expect(serie['distance_m'], isNotNull);
  });
}
