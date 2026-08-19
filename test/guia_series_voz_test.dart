// ============================================================
//  La sesión de series, minuto a minuto, tal como la va a oír el deportista.
//
//  Se recorre el bloque entero segundo a segundo y se apunta TODO lo que dice
//  la voz. Es la única forma de contestar a «¿me irá diciendo serie 1, ahora
//  descanso, ahora serie 2?» sin salir a correr a comprobarlo.
//
//  ⚠️ Y aquí se destapó un fallo que no se ve leyendo el código de un vistazo:
//  el bloque arrancaba llamando a `_startIntervalRest`, así que el deportista
//  se quedaba parado los 90 segundos de la recuperación ANTES de la serie 1 —
//  en silencio— y el bloque duraba un descanso de más.
// ============================================================
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ritmooptimo_mobile/core/audio/salida_de_audio.dart';
import 'package:ritmooptimo_mobile/core/audio/session_audio_controller.dart';

/// Un servicio de audio que no suena: solo apunta lo que le piden decir.
class AudioEspia implements SalidaDeAudio {
  final List<String> dicho = [];
  final List<String> sonado = [];

  @override
  Future<void> startSession() async {}
  @override
  Future<void> stopSession() async {}
  @override
  Future<void> speak(String text) async => dicho.add(text);
  @override
  Future<void> beepShort() async => sonado.add('beep');
  @override
  Future<void> beepLong() async => sonado.add('BEEP');
  @override
  Future<void> countdown5() async => sonado.add('cuenta-atras-5');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // La sesión del viernes, tal cual la guarda ahora el backend.
  final bloques = <Map<String, dynamic>>[
    {'block': 'Calentamiento', 'type': 'warmup', 'min': 1, 'zone': 'R1'},
    {
      'block': 'Series 3 x 8 min', 'type': 'intervals', 'min': 27, 'zone': 'R2',
      'reps': 3, 'rep_duration_min': 8, 'recovery_seconds': 90,
      'recovery_zone': 'R1', 'target_pace': '4:30',
    },
    {'block': 'Vuelta a la calma', 'type': 'cooldown', 'min': 1, 'zone': 'R1'},
  ];

  /// Corre la sesión entera y devuelve lo que se ha ido diciendo, con el
  /// segundo en el que se dijo.
  ///
  /// ⚠️ Con reloj FALSO. El controlador tiene esperas reales de 1,8 s entre
  /// bloques; con el reloj de verdad, el bucle avanzaría los segundos mientras
  /// el controlador sigue esperando y se perderían los avisos. Y una sesión de
  /// 27 minutos tampoco se puede probar en tiempo real.
  List<(int, String)> correr({int hasta = 2400}) {
    final guion = <(int, String)>[];
    fakeAsync((async) {
      final espia = AudioEspia();
      final c = SessionAudioController(audio: espia, rawBlocks: bloques);
      var vistas = 0;

      c.onSessionStart();
      async.flushMicrotasks();

      for (var t = 0; t <= hasta; t++) {
        c.onTick(t, distanceM: t * 3);        // ~3 m/s, un ritmo plausible
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        while (vistas < espia.dicho.length) {
          guion.add((t, espia.dicho[vistas]));
          vistas++;
        }
      }
    });
    return guion;
  }

  test('el bloque de series EMPIEZA corriendo, no descansando', () {
    final guion = correr(hasta: 200);

    final iSerie1 = guion.indexWhere((g) => g.$2.contains('Serie 1 de 3'));
    final iDescanso = guion.indexWhere((g) => g.$2.startsWith('Descansa'));

    expect(iSerie1, greaterThanOrEqualTo(0), reason: 'nunca anunció la serie 1');
    expect(iDescanso == -1 || iSerie1 < iDescanso, isTrue,
        reason: 'el primer descanso no puede ir ANTES de la primera serie');

    // Y arranca en cuanto acaba el calentamiento, no 90 s después.
    final segundoSerie1 = guion.firstWhere((g) => g.$2.contains('Serie 1 de 3')).$1;
    expect(segundoSerie1, lessThan(90),
        reason: 'esperó un descanso entero antes de empezar: arrancó en el segundo $segundoSerie1');
  });

  test('anuncia las tres series y los dos descansos, en orden', () {
    final guion = correr();
    final frases = guion.map((g) => g.$2).toList();

    final orden = frases.where((f) =>
        f.contains('Serie 1 de 3') || f.contains('Serie 2 de 3') ||
        f.contains('Serie 3 de 3') || f.startsWith('Descansa')).toList();

    expect(orden.length, 5, reason: '3 series + 2 descansos. Salió: $orden');
    expect(orden[0], contains('Serie 1 de 3'));
    expect(orden[1], startsWith('Descansa'));
    expect(orden[2], contains('Serie 2 de 3'));
    expect(orden[3], startsWith('Descansa'));
    expect(orden[4], contains('Serie 3 de 3'));

    // ⚠️ Después de la última serie NO hay descanso: viene la vuelta a la calma.
    expect(frases.where((f) => f.startsWith('Descansa')).length, 2);
  });

  test('dice el ritmo objetivo al empezar cada serie larga', () {
    final guion = correr();
    final series = guion.map((g) => g.$2).where((f) => f.contains('de 3. ')).toList();
    expect(series.every((f) => f.contains('4 minutos 30 segundos')), isTrue,
        reason: 'en repeticiones de 8 min da tiempo a decirlo. Salió: $series');
  });

  test('avisa a falta de 10 segundos, y dice QUÉ viene después', () {
    final guion = correr();
    final frases = guion.map((g) => g.$2).toList();

    expect(frases.where((f) => f.contains('Últimos 10 segundos')).length, 3,
        reason: 'un aviso por serie');
    expect(frases.any((f) => f.contains('En 10 segundos, serie 2 de 3')), isTrue);
    expect(frases.any((f) => f.contains('En 10 segundos, serie 3 de 3')), isTrue);
  });

  test('la cuenta cuadra: el bloque dura lo que dice el plan', () {
    final guion = correr();
    final t0 = guion.firstWhere((g) => g.$2.contains('Serie 1 de 3')).$1;
    final tFin = guion.firstWhere((g) => g.$2.contains('Bloque 2 completado')).$1;

    // 3 x 8 min + 2 x 90 s = 27 min = 1620 s (con unos segundos de margen por
    // las frases que se dicen entre medias).
    expect(tFin - t0, closeTo(1620, 15),
        reason: 'el bloque duró ${tFin - t0} s y el plan dice 1620');
  });

  test('la PRIMERA serie mide su propio ritmo, no el de toda la sesion', () {
    // Corriendo a 3 m/s constantes, cada serie va a 5:33/km. Si la primera
    // midiera desde el inicio de la sesion daria un ritmo absurdo (1:55) y
    // encima con veredicto "algo rapido": un dato inventado con consejo encima.
    final guion = correr();
    final r1 = guion.firstWhere((g) => g.$2.startsWith('Serie 1 completada')).$2;
    final r2 = guion.firstWhere((g) => g.$2.startsWith('Serie 2 completada')).$2;
    // El ritmo de la primera y el de la segunda tienen que parecerse: van
    // exactamente igual de rapido. La firma del fallo era un ritmo ABSURDO en
    // la primera (1:55 corriendo a 5:33).
    final min1 = int.parse(RegExp(r"Ritmo: (\d+) minutos?").firstMatch(r1)!.group(1)!);
    final min2 = int.parse(RegExp(r"Ritmo: (\d+) minutos?").firstMatch(r2)!.group(1)!);
    expect(min1, min2, reason: 'serie 1 dijo $r1 y serie 2 dijo $r2');
    expect(min1, greaterThanOrEqualTo(5),
        reason: 'un ritmo de menos de 5 min/km corriendo a 3 m/s es inventado');
  });

  test('cierra diciendo cuántas series se hicieron', () {
    final guion = correr();
    expect(guion.any((g) => g.$2.contains('3 de 3 series realizadas')), isTrue);
  });
}
