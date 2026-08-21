// ============================================================
//  LAS SERIES TIENEN QUE DECIR LA ZONA Y LAS PULSACIONES
//
//  ⚠️ LA SESIÓN DEL 21/08/2026, TAL COMO ESTÁ EN LA BASE:
//
//      Calentamiento     15 min · R1 · escala=percepcion · sin ritmo
//      Series 3 x 8 min  27 min · R2 · escala=percepcion · sin ritmo
//      Vuelta a la calma 13 min · R1 · escala=percepcion · sin ritmo
//
//  El deportista corrió 56 minutos y NO OYÓ NI UNA REFERENCIA. Dos causas, y
//  las dos parecían decisiones razonables por separado:
//
//   1. `targetDescription` decía la zona solo cuando era un número de FC. Con
//      R2, `zonaFcNumero` devuelve null A PROPÓSITO —para no pintar R2 como Z2,
//      que costó treinta pulsaciones de error— así que la frase salía VACÍA.
//
//   2. El aviso se callaba en escala de percepción, porque traducir R1 con una
//      fórmula genérica sería inventar una equivalencia. Correcto… salvo que
//      este deportista tiene TODO su plan en R y ninguna equivalencia propia:
//      el resultado fue silencio absoluto.
//
//  Ninguna de las dos daba error. Las dos "funcionaban".
// ============================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:ritmooptimo_mobile/core/audio/session_audio_controller.dart';
import 'package:ritmooptimo_mobile/core/audio/audio_cue_service.dart';
import 'package:ritmooptimo_mobile/core/session/aviso_zona.dart';

class _VozFalsa implements AudioCueService {
  final dicho = <String>[];
  @override
  Future<void> speak(String texto, {bool interrumpe = false}) async => dicho.add(texto);
  @override
  Future<void> startSession() async {}
  @override
  Future<void> stopSession() async {}
  @override
  noSuchMethod(Invocation i) => Future.value();
}

void main() {
  // Las de David: FC de reserva sobre su reposo (55, del reloj) y su máxima
  // (178, vista en sesión), con las fracciones de SUS zonas.
  const zonasR = [
    RangoFc(desde: 110, hasta: 129, nombre: 'R0',  esEstimacion: true),
    RangoFc(desde: 129, hasta: 141, nombre: 'R1',  esEstimacion: true),
    RangoFc(desde: 141, hasta: 153, nombre: 'R1+', esEstimacion: true),
    RangoFc(desde: 153, hasta: 163, nombre: 'R2',  esEstimacion: true),
    RangoFc(desde: 163, hasta: 172, nombre: 'R3',  esEstimacion: true),
    RangoFc(desde: 172, hasta: 178, nombre: 'R3+', esEstimacion: true),
  ];

  final sesionDeHoy = <Map<String, dynamic>>[
    {'block': 'Calentamiento', 'min': 15, 'zone': 'R1', 'zone_escala': 'percepcion'},
    {'block': 'Series 3 x 8 min', 'type': 'series', 'min': 27, 'zone': 'R2',
     'zone_escala': 'percepcion', 'reps': 3, 'rep_duration_min': 8,
     'recovery_seconds': 90},
    {'block': 'Vuelta a la calma', 'min': 13, 'zone': 'R1', 'zone_escala': 'percepcion'},
  ];

  /// ⚠️ Solo el bloque de series. La primera versión de este test corría la
  /// sesión ENTERA a 158 esperando silencio "porque está en R2"… pero los
  /// primeros quince minutos son el calentamiento en R1 (129-141), así que 158
  /// SÍ es salirse. El aviso funcionaba; el test estaba mal planteado.
  final soloLasSeries = <Map<String, dynamic>>[
    {'block': 'Series 3 x 8 min', 'type': 'series', 'min': 27, 'zone': 'R2',
     'zone_escala': 'percepcion', 'reps': 3, 'rep_duration_min': 8,
     'recovery_seconds': 90},
  ];

  ({SessionAudioController c, _VozFalsa v}) montar(
    List<Map<String, dynamic>> bloques, {
    List<RangoFc>? entrenador,
    List<RangoFc>? equivalencia,
  }) {
    final v = _VozFalsa();
    return (
      c: SessionAudioController(
        audio: v, rawBlocks: bloques,
        zonasEntrenador: entrenador, equivalencia: equivalencia),
      v: v,
    );
  }

  /// ⚠️ HAY QUE DEJARLE RESPIRAR ENTRE TICKS. `onTick` lanza trabajo asíncrono
  /// —hablar, cambiar de fase— y en un bucle síncrono nada de eso llega a
  /// ocurrir: el bloque no arranca y la lista de frases sale vacía. Sin esta
  /// pausa el test fallaría por su propia forma, no por el código.
  Future<void> correrSesion(({SessionAudioController c, _VozFalsa v}) m,
      {required int hasta, int? hr}) async {
    await m.c.onSessionStart();
    for (var s = 0; s <= hasta; s++) {
      m.c.onTick(s, distanceM: s * 3, hr: hr);
      if (s % 20 == 0) await Future.delayed(const Duration(milliseconds: 6));
    }
    await Future.delayed(const Duration(milliseconds: 250));
  }

  String todo(_VozFalsa v) => v.dicho.join(' | ').toLowerCase();
  List<String> avisos(_VozFalsa v) => v.dicho
      .where((t) => t.contains('Afloja') || t.contains('apretar'))
      .toList();

  // ── 1. LA ZONA SE DICE SIEMPRE ──────────────────────────────────────
  test('dice la zona del entrenador aunque no haya pulsaciones que dar', () async {
    final m = montar(sesionDeHoy);
    await correrSesion(m, hasta: 60);
    expect(todo(m.v), contains('en r1'),
        reason: 'el calentamiento va en R1 y hay que decirlo');
  });

  // ── 2. Y CON LAS ZONAS DEL ENTRENADOR, TAMBIÉN LAS PULSACIONES ──────
  test('con las zonas del entrenador dice el rango, Y que es estimado', () async {
    final m = montar(sesionDeHoy, entrenador: zonasR);
    await correrSesion(m, hasta: 60, hr: 135);
    final t = todo(m.v);
    expect(t, contains('en r1'));
    expect(t, contains('pulsaciones: entre 129 y 141'));
    // ⚠️ Sin esto sería un rango calculado presentado como su umbral medido.
    expect(t, contains('estimadas'),
        reason: 'un dato sin procedencia no se le da a nadie');
  });

  // ── 3. ⚠️ SIN ZONAS NO SE INVENTA NINGÚN NÚMERO ─────────────────────
  //
  // La regla que NO se ha tocado. Antes se callaba TODO; ahora solo lo que no
  // sabe: dice la zona, y de pulsaciones no dice nada.
  test('sin zonas del entrenador no se inventa ninguna pulsación', () async {
    final m = montar(sesionDeHoy);
    await correrSesion(m, hasta: 60, hr: 135);
    expect(todo(m.v), isNot(contains('pulsaciones:')));
  });

  // ── 4. EL AVISO EN LAS SERIES (R2 = 153-163) ────────────────────────
  group('el aviso, en el bloque de series', () {
    Future<List<String>> aFc(int hr) async {
      final m = montar(soloLasSeries, entrenador: zonasR);
      await correrSesion(m, hasta: 400, hr: hr);
      return avisos(m.v);
    }

    test('dentro de R2 no se le dice nada', () async {
      expect(await aFc(158), isEmpty);
    });

    // ⚠️ EL MARGEN DE 5. El borde de una zona no es una pared —y menos con un
    // rango estimado—: rozarlo no es salirse. Sin margen, quien corra justo en
    // el límite (lo normal en umbral) se come avisos por una pulsación.
    test('rozando el techo (+5) tampoco', () async {
      expect(await aFc(167), isEmpty, reason: '163 + 5 = 168; 167 aún no');
    });

    test('rozando el suelo (-5) tampoco', () async {
      expect(await aFc(149), isEmpty, reason: '153 - 5 = 148; 149 aún no');
    });

    test('pasado el margen por arriba, SÍ avisa', () async {
      final d = await aFc(178);
      expect(d, isNotEmpty, reason: '178 se sale de 163+5 con creces');
      expect(d.first, contains('Afloja'));
      expect(d.first, contains('R2'), reason: 'y dice respecto a qué');
    });

    test('pasado el margen por abajo, SÍ avisa', () async {
      final d = await aFc(130);
      expect(d, isNotEmpty, reason: '130 está por debajo de 153-5');
      expect(d.first, contains('apretar'));
    });

    // ⚠️ Decirle «aprieta» con un número muerto es peor que callarse.
    test('sin lectura de la banda no avisa de nada', () async {
      final m = montar(soloLasSeries, entrenador: zonasR);
      await correrSesion(m, hasta: 400);
      expect(avisos(m.v), isEmpty);
    });
  });

  // ── 5. LA EQUIVALENCIA PROPIA MANDA SOBRE LA ESTIMACIÓN ─────────────
  test('si hay equivalencia propia medida, gana a la estimada', () async {
    final m = montar(sesionDeHoy,
        entrenador: zonasR,
        equivalencia: const [RangoFc(desde: 145, hasta: 158, nombre: 'R1')]);
    await correrSesion(m, hasta: 60, hr: 150);
    final t = todo(m.v);
    expect(t, contains('entre 145 y 158'), reason: 'la suya, no la calculada');
    expect(t, isNot(contains('entre 129 y 141')));
    expect(t, isNot(contains('estimadas')),
        reason: 'una medida no se anuncia como estimación');
  });
}
