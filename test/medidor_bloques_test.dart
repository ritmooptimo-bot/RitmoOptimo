// ═══════════════════════════════════════════════════════════════
//  Cada bloque con sus propias medidas
//
//  "El bloque 1 debe tomar sus medidas independientes de los demás… para que el
//   deportista sepa cómo ha realizado el bloque concreto." — David, 07/08
//
//  Lo que se prueba aquí es que el bloque 2 empieza en CERO aunque la sesión
//  lleve ya kilómetros encima, y que los números hablados no se leen como una
//  hora — que es un fallo que ya cometimos y que él reportó.
// ═══════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:ritmooptimo_mobile/core/audio/medidor_bloques.dart';

void main() {
  group('MedidorBloque · cada bloque empieza en cero', () {
    test('el bloque 2 no hereda los kilómetros del bloque 1', () {
      // La sesión lleva 600 s y 1500 m cuando arranca el segundo bloque.
      final m = MedidorBloque(
        indice: 1, etiqueta: 'Parte principal',
        elapsedSeg: 600, metrosTotales: 1500, segundosPrevistos: 2700,
      );
      m.anota(elapsedSeg: 1200, metrosTotales: 3200, fc: 145);

      expect(m.segundos, 600, reason: '10 min de bloque, no los 20 de sesión');
      expect(m.metros, 1700, reason: '1,7 km de bloque, no los 3,2 de sesión');
    });

    test('el GPS corrigiendo hacia atrás no resta distancia ya recorrida', () {
      final m = MedidorBloque(indice: 0, etiqueta: 'X', elapsedSeg: 0, metrosTotales: 0);
      m.anota(elapsedSeg: 60, metrosTotales: 300);
      m.anota(elapsedSeg: 61, metrosTotales: 280);   // el GPS se echa atrás
      expect(m.metros, 300);
    });

    test('descarta pulsaciones imposibles', () {
      final m = MedidorBloque(indice: 0, etiqueta: 'X', elapsedSeg: 0, metrosTotales: 0);
      for (final fc in [140, 150, 5, 260, 160]) {
        m.anota(elapsedSeg: 10, metrosTotales: 100, fc: fc);
      }
      final r = m.cerrar();
      expect(r.fcMedia, 150, reason: 'media de 140, 150 y 160');
      expect(r.fcMax, 160, reason: '260 no es una pulsación');
    });

    test('sin banda, no inventa pulso', () {
      final m = MedidorBloque(indice: 0, etiqueta: 'X', elapsedSeg: 0, metrosTotales: 0);
      m.anota(elapsedSeg: 60, metrosTotales: 200);
      final r = m.cerrar();
      expect(r.fcMedia, isNull);
      expect(r.fcMax, isNull);
    });
  });

  group('ResultadoBloque · ritmo', () {
    test('calcula el ritmo del bloque', () {
      const r = ResultadoBloque(indice: 0, etiqueta: 'X', segundosPrevistos: 600,
          segundosReales: 600, metros: 2000);
      expect(r.ritmoSegPorKm, 300);   // 10 min / 2 km = 5:00
    });

    test('con menos de 100 m NO da ritmo: sería ruido del GPS', () {
      // Un bloque de fuerza en el salón daría "2:30/km" si no se filtrara.
      const r = ResultadoBloque(indice: 0, etiqueta: 'Fuerza', segundosPrevistos: 600,
          segundosReales: 600, metros: 40);
      expect(r.ritmoSegPorKm, isNull);
    });

    test('descarta ritmos fuera de lo humano', () {
      const rapido = ResultadoBloque(indice: 0, etiqueta: 'X', segundosPrevistos: 0,
          segundosReales: 60, metros: 1000);          // 1:00/km
      const lento = ResultadoBloque(indice: 0, etiqueta: 'X', segundosPrevistos: 0,
          segundosReales: 2000, metros: 1000);        // 33 min/km
      expect(rapido.ritmoSegPorKm, isNull);
      expect(lento.ritmoSegPorKm, isNull);
    });
  });

  group('la voz · nunca un ritmo que suene a hora', () {
    test('los ritmos hablados van en palabras', () {
      // ⚠️ "5:42" el motor lo lee como "las cinco cuarenta y dos". Ya pasó con
      // el aviso de kilómetro y David lo reportó.
      expect(ritmoHablado(342), '5 minutos y 42 segundos por kilómetro');
      expect(ritmoHablado(300), '5 minutos por kilómetro');
      expect(ritmoHablado(342), isNot(contains(':')));
      expect(ritmoHablado(300), isNot(contains(':')));
    });

    test('el texto escrito sí lleva los dos puntos', () {
      expect(ritmoTexto(342), '5:42');
      expect(ritmoTexto(300), '5:00');
      expect(ritmoTexto(65), '1:05');
    });
  });

  group('el veredicto del bloque', () {
    ResultadoBloque hecho({int metros = 2000, int seg = 600, int? fc}) =>
        ResultadoBloque(indice: 0, etiqueta: 'Parte principal',
            segundosPrevistos: 600, segundosReales: seg, metros: metros, fcMedia: fc);

    test('dice lo hecho y compara con lo que pedía el entrenador', () {
      final v = veredictoBloque(hecho(), ritmoObjetivoSegKm: 300);
      expect(v, contains('Bloque 1 completado'));
      expect(v, contains('justo en el ritmo que pedía tu entrenador'));
      expect(v, isNot(contains(':')), reason: 'nada que la voz lea como una hora');
    });

    test('avisa si fue más rápido o más lento', () {
      expect(veredictoBloque(hecho(seg: 660), ritmoObjetivoSegKm: 300),
          contains('30 segundos más lento'));
      expect(veredictoBloque(hecho(seg: 540), ritmoObjetivoSegKm: 300),
          contains('30 segundos más rápido'));
    });

    test('sin ritmo objetivo cuenta lo hecho pero NO juzga', () {
      final v = veredictoBloque(hecho());
      expect(v, contains('Bloque 1 completado'));
      expect(v, isNot(contains('previsto')));
      expect(v, isNot(contains('entrenador')));
    });

    test('un bloque sin distancia (fuerza) no habla de kilómetros', () {
      final v = veredictoBloque(hecho(metros: 20));
      expect(v, 'Bloque 1 completado.');
    });

    test('menciona el pulso si lo hubo', () {
      expect(veredictoBloque(hecho(fc: 148)), contains('pulso medio 148'));
    });
  });

  group('lo que se envía al backend', () {
    test('lleva lo previsto y lo real, para poder compararlos', () {
      const r = ResultadoBloque(indice: 0, etiqueta: 'Calentamiento', zona: 'R1',
          segundosPrevistos: 600, segundosReales: 640, metros: 1800, fcMedia: 132, fcMax: 141);
      final j = r.toJson();
      expect(j['block'], 'Calentamiento');
      expect(j['zone'], 'R1');
      expect(j['min'], 11);
      expect(j['min_previstos'], 10);
      expect(j['distance_m'], 1800);
      expect(j['hr_avg'], 132);
      expect(j['hr_max'], 141);
      expect(j['pace_sec_km'], isNotNull);
    });
  });
}
