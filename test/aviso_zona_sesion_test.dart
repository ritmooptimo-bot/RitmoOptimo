import 'package:flutter_test/flutter_test.dart';
import 'package:ritmooptimo_mobile/core/audio/session_audio_controller.dart';
import 'package:ritmooptimo_mobile/core/audio/audio_cue_service.dart';
import 'package:ritmooptimo_mobile/core/session/aviso_zona.dart';

/// El aviso, ya montado en la sesión de verdad.
///
/// ⚠️ LA REGLA QUE SE PROTEGE AQUÍ: se avisa por pulsaciones SOLO en los bloques
/// cuya escala es de frecuencia cardiaca. En un bloque `R1` de Raúl —percepción
/// pura, «sin reloj ni pulsómetro»— la app se calla, aunque vaya a 190.
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
  const zonas = [
    RangoFc(desde: 0,   hasta: 107, nombre: 'Z1 Muy suave'),
    RangoFc(desde: 107, hasta: 125, nombre: 'Z2 Suave'),
    RangoFc(desde: 125, hasta: 142, nombre: 'Z3 Moderado'),
    RangoFc(desde: 142, hasta: 160, nombre: 'Z4 Intenso'),
    RangoFc(desde: 160,              nombre: 'Z5 Máximo'),
  ];

  ({SessionAudioController c, _VozFalsa v, List<int> vibras}) montar(
      List<Map<String, dynamic>> bloques) {
    final v = _VozFalsa();
    final vibras = <int>[];
    final c = SessionAudioController(
      audio: v, rawBlocks: bloques, zonasFc: zonas,
      onVibrar: () => vibras.add(1));
    return (c: c, v: v, vibras: vibras);
  }

  List<String> avisos(_VozFalsa v) =>
      v.dicho.where((t) => t.contains('Afloja') || t.contains('apretar')).toList();

  test('en un bloque de FC, avisa cuando se pasa', () {
    final m = montar([
      {'block': 'Parte principal', 'min': 40, 'zone': '2', 'zone_escala': 'fc'},
    ]);
    for (var s = 0; s < 120; s++) {
      m.c.onTick(s, distanceM: s * 3, hr: 150);   // Z4, pedía Z2
    }
    expect(avisos(m.v).length, greaterThanOrEqualTo(1));
    expect(avisos(m.v).first, contains('107-125 ppm'));
    expect(m.vibras.length, 1);
  });

  test('EN UN BLOQUE R1 NO AVISA, aunque vaya a 190', () {
    final m = montar([
      {'block': 'Rodaje', 'min': 40, 'zone': 'R1', 'zone_escala': 'percepcion'},
    ]);
    for (var s = 0; s < 600; s++) {
      m.c.onTick(s, distanceM: s * 3, hr: 190);
    }
    expect(avisos(m.v), isEmpty);
    expect(m.vibras, isEmpty);
  });

  test('sin zonas cargadas (sin red o sin FC máxima) tampoco avisa', () {
    final v = _VozFalsa();
    final c = SessionAudioController(
      audio: v, zonasFc: null,
      rawBlocks: [{'block': 'Parte principal', 'min': 40, 'zone': '2', 'zone_escala': 'fc'}]);
    for (var s = 0; s < 600; s++) {
      c.onTick(s, distanceM: s * 3, hr: 190);
    }
    expect(avisos(v), isEmpty);
  });

  test('con la banda suelta (sin FC) no avisa: no sabe a qué va', () {
    final m = montar([
      {'block': 'Parte principal', 'min': 40, 'zone': '2', 'zone_escala': 'fc'},
    ]);
    for (var s = 0; s < 600; s++) {
      m.c.onTick(s, distanceM: s * 3, hr: null);
    }
    expect(avisos(m.v), isEmpty);
  });

  _equivalencia();

  test('una hora entera fuera de zona no pasa del tope de la sesión', () {
    final m = montar([
      {'block': 'Parte principal', 'min': 60, 'zone': '2', 'zone_escala': 'fc'},
    ]);
    for (var s = 0; s < 3600; s++) {
      m.c.onTick(s, distanceM: s * 3, hr: 155);
    }
    expect(avisos(m.v).length, AvisoZona.maximoAvisos);
  });
}

/// LA EQUIVALENCIA DEL DEPORTISTA — lo que hace posible avisar en un bloque R1.
///
/// ⚠️ Y la distinción que lo sostiene: con un rango OBSERVADO se le describe,
/// con uno FIRMADO por el entrenador se le corrige. Si corre sus suaves
/// demasiado fuerte, ordenarle sobre su propia costumbre le daría la razón.
void _equivalencia() {
  const observado = RangoFc(desde: 134, hasta: 151, nombre: 'R1',
                            mandaElEntrenador: false);
  const firmado = RangoFc(desde: 120, hasta: 135, nombre: 'R1',
                          mandaElEntrenador: true);

  List<String> correr(SessionAudioController c, int segs, int hr) {
    for (var s = 0; s < segs; s++) {
      c.onTick(s, distanceM: s * 3, hr: hr);
    }
    return <String>[];
  }

  test('con equivalencia OBSERVADA describe, no ordena', () {
    final v = _VozFalsa();
    final c = SessionAudioController(
      audio: v, equivalencia: const [observado],
      rawBlocks: [{'block': 'Rodaje', 'min': 40, 'zone': 'R1', 'zone_escala': 'percepcion'}]);
    correr(c, 200, 165);
    final dichos = v.dicho.where((t) => t.contains('165')).toList();
    expect(dichos, isNotEmpty);
    expect(dichos.first, contains('sueles ir entre 134 y 151'));
    expect(dichos.first, isNot(contains('Afloja')));
  });

  test('con equivalencia FIRMADA por el entrenador sí corrige', () {
    final v = _VozFalsa();
    final c = SessionAudioController(
      audio: v, equivalencia: const [firmado],
      rawBlocks: [{'block': 'Rodaje', 'min': 40, 'zone': 'R1', 'zone_escala': 'percepcion'}]);
    correr(c, 200, 165);
    final dichos = v.dicho.where((t) => t.contains('165')).toList();
    expect(dichos.first, contains('Afloja'));
    expect(dichos.first, contains('120-135 ppm'));
  });

  test('SIN equivalencia, un bloque R1 sigue sin avisar de nada', () {
    final v = _VozFalsa();
    final c = SessionAudioController(
      audio: v, equivalencia: const [],
      rawBlocks: [{'block': 'Rodaje', 'min': 40, 'zone': 'R1', 'zone_escala': 'percepcion'}]);
    correr(c, 600, 190);
    expect(v.dicho.where((t) => t.contains('190')), isEmpty);
  });

  test('la equivalencia manda sobre el modelo genérico de zonas', () {
    // El bloque dice zona 2 en escala de FC (Z2 = 107-125), pero la equivalencia
    // del deportista para esa etiqueta dice otra cosa: gana la suya.
    final v = _VozFalsa();
    final c = SessionAudioController(
      audio: v,
      zonasFc: const [RangoFc(desde: 107, hasta: 125, nombre: 'Z2 Suave')],
      equivalencia: const [RangoFc(desde: 150, hasta: 165, nombre: '2')],
      rawBlocks: [{'block': 'Principal', 'min': 40, 'zone': '2', 'zone_escala': 'fc'}]);
    correr(c, 200, 120);   // 120 está DENTRO de Z2 genérica, FUERA de la suya
    expect(v.dicho.where((t) => t.contains('120')), isNotEmpty);
  });
}
