// ============================================================
//  CADA KILÓMETRO TIENE QUE DECIR LA FC Y LA ZONA
//
//  Petición del entrenador (21/08): «que cada km me dé el ritmo del km, el
//  tiempo, etc., y además la FC y la R o zona que determine el plan, así sé que
//  está todo dentro».
//
//  Antes el aviso del kilómetro solo llevaba ritmo, media y tiempo total. La
//  zona y el rango se decían UNA vez, al empezar el bloque — y en un rodaje de
//  hora y media eso queda muy atrás.
//
//  ⚠️ Y LA TRAMPA DE ESTO NO ES DECIR EL NÚMERO: es NO decirlo cuando ya no
//  vale. Una FC congelada es peor que ninguna. Ya pasó —cuarenta minutos de
//  sesión con el mismo 126 porque la banda se había soltado— y aquí sería peor
//  todavía: el mismo número repetido kilómetro tras kilómetro, sonando a que
//  todo va perfecto.
// ============================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:ritmooptimo_mobile/core/audio/session_audio_controller.dart';
import 'package:ritmooptimo_mobile/core/audio/audio_cue_service.dart';

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
  /// El rodaje largo del domingo: 90 minutos en R1.
  final rodajeLargo = <Map<String, dynamic>>[
    {'block': 'Parte principal', 'min': 90, 'zone': 'R1', 'zone_escala': 'percepcion'},
  ];

  /// Y una sesión en escala de FC, para ver que ahí dice «zona 2» y no «z2».
  final enZonaFc = <Map<String, dynamic>>[
    {'block': 'Rodaje', 'min': 60, 'zone': 'z2', 'zone_escala': 'fc'},
  ];

  /// Corre [metros] a 5:00/km dando el pulso que devuelva [fcEn].
  /// `fcEn` recibe el segundo y devuelve null cuando la banda no da nada.
  Future<_VozFalsa> correr(
    List<Map<String, dynamic>> bloques, {
    required int metros,
    required int? Function(int seg) fcEn,
  }) async {
    final v = _VozFalsa();
    final c = SessionAudioController(audio: v, rawBlocks: bloques);
    await c.onSessionStart();
    // 5:00/km = 3,33 m/s. Se avanza segundo a segundo.
    final segundos = (metros / 3.33).round();
    for (var s = 0; s <= segundos; s++) {
      c.onTick(s, distanceM: (s * 3.33).round(), hr: fcEn(s));
      if (s % 20 == 0) await Future.delayed(const Duration(milliseconds: 4));
    }
    await Future.delayed(const Duration(milliseconds: 250));
    return v;
  }

  // ⚠️ Estos son `test`, NO `testWidgets`. Con testWidgets el reloj es FALSO y
  // un `Future.delayed` no avanza si nadie hace `pump`: el test se queda
  // colgado para siempre en vez de fallar, que es la peor forma de fallar.
  // Aquí no se pinta nada, así que testWidgets no pinta nada tampoco.
  List<String> kms(_VozFalsa v) =>
      v.dicho.where((t) => t.startsWith('Kilómetro ')).toList();

  // ── 1. LO QUE PIDIÓ ─────────────────────────────────────────────────
  test('cada kilómetro dice ritmo, tiempo, FC y zona', () async {
    final v = await correr(rodajeLargo, metros: 2100, fcEn: (_) => 136);
    final k = kms(v);
    expect(k.length, greaterThanOrEqualTo(2), reason: 'dos kilómetros completos');
    for (final linea in k) {
      expect(linea, contains('Último kilómetro en'));
      expect(linea, contains('Tiempo total'));
      expect(linea, contains('Vas a 136'), reason: 'la FC de ahora');
      expect(linea, contains('en R1'), reason: 'y la zona que pide el plan');
    }
  });

  test('en escala de FC dice «zona 2», no «z2»', () async {
    // «z2» lo lee el motor de voz como «zeta dos».
    final v = await correr(enZonaFc, metros: 1100, fcEn: (_) => 128);
    expect(kms(v).first, contains('en zona 2'));
    expect(kms(v).first, isNot(contains('en z2')));
  });

  // ── 2. ⚠️ SIN LECTURA FRESCA, NI UNA PALABRA DE PULSO ───────────────
  test('sin banda no dice ninguna FC, pero sigue dando el ritmo', () async {
    final v = await correr(rodajeLargo, metros: 2100, fcEn: (_) => null);
    final k = kms(v);
    expect(k, isNotEmpty);
    for (final linea in k) {
      expect(linea, contains('Último kilómetro en'), reason: 'el ritmo sí');
      expect(linea, isNot(contains('Vas a')), reason: 'el pulso no se inventa');
    }
  });

  // ⚠️ LA QUE DE VERDAD IMPORTA. La banda da 126 y se suelta al minuto: sin
  // control de frescura, ese 126 se repetiría kilómetro tras kilómetro sonando
  // a que todo va perfecto.
  test('si la banda se suelta, DEJA de decir el último número', () async {
    final v = await correr(rodajeLargo,
        metros: 3100, fcEn: (s) => s < 60 ? 126 : null);
    final k = kms(v);
    expect(k.length, greaterThanOrEqualTo(3));
    // El primer km (a los ~300 s) ya está fuera de la ventana de frescura.
    for (final linea in k) {
      expect(linea, isNot(contains('Vas a 126')),
          reason: 'ese 126 es de hace minutos: repetirlo es mentir con cara de dato');
    }
  });

  // ── 3. El número que se dice es el de AHORA ─────────────────────────
  test('con el pulso subiendo, cada km dice el suyo', () async {
    // 130 el primer km, 150 el segundo.
    //
    // ⚠️ El corte va en el segundo 400, no en el 300. El kilómetro 1 se anuncia
    // sobre el 301 —hay una cuenta atrás por delante— y cortando justo en 300
    // el primer aviso ya cogía 150: el test fallaba por un segundo, no por el
    // código.
    final v = await correr(rodajeLargo,
        metros: 2100, fcEn: (s) => s < 400 ? 130 : 150);
    final k = kms(v);
    expect(k.length, greaterThanOrEqualTo(2));
    expect(k[0], contains('Vas a 130'));
    expect(k[1], contains('Vas a 150'),
        reason: 'no se queda con el del kilómetro anterior');
  });
}
