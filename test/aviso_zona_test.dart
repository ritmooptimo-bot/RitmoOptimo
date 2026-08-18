import 'package:flutter_test/flutter_test.dart';
import 'package:ritmooptimo_mobile/core/session/aviso_zona.dart';

/// ⚠️ LO QUE SE PRUEBA AQUÍ NO ES SI DETECTA QUE SE HA SALIDO —eso es una
/// comparación— SINO **CUÁNTAS VECES ABRE LA BOCA**. Un aviso cada tres segundos
/// se aprende a ignorar en dos minutos, y a partir de ahí la función está muerta
/// aunque funcione perfectamente.
void main() {
  const z2 = RangoFc(desde: 107, hasta: 125, nombre: 'Z2 Suave');

  /// Corre `segundos` segundos con una FC fija y devuelve lo que ha dicho.
  List<String> correr(AvisoZona a, int desde, int segundos, int? bpm) {
    final dicho = <String>[];
    for (var s = desde; s < desde + segundos; s++) {
      final r = a.tick(s, bpm);
      if (r.decir != null) dicho.add(r.decir!);
    }
    return dicho;
  }

  group('cuándo NO se abre la boca', () {
    test('en escala de percepción NO se avisa nunca, vaya como vaya', () {
      // La escala R de Raúl es «sin reloj ni pulsómetro»: avisar por pulsaciones
      // en un bloque R1 sería entrenar contra su método.
      final a = AvisoZona(objetivo: z2, escala: 'percepcion');
      expect(a.aplica, isFalse);
      expect(correr(a, 0, 600, 190), isEmpty);
      expect(a.estado, EstadoZona.noAplica);
    });

    test('sin objetivo tampoco', () {
      final a = AvisoZona(objetivo: null, escala: 'fc');
      expect(correr(a, 0, 600, 190), isEmpty);
    });

    test('SIN LECTURA de la banda no se avisa: no se sabe a qué va', () {
      final a = AvisoZona(objetivo: z2, escala: 'fc');
      expect(correr(a, 0, 600, null), isEmpty);
      expect(a.estado, EstadoZona.sinDato);
    });

    test('un pico corto —una cuesta, un semáforo— no es salirse', () {
      final a = AvisoZona(objetivo: z2, escala: 'fc');
      expect(correr(a, 0, AvisoZona.persistenciaSeg - 1, 150), isEmpty);
    });

    test('y si vuelve a zona, la cuenta se reinicia', () {
      final a = AvisoZona(objetivo: z2, escala: 'fc');
      correr(a, 0, 15, 150);           // 15 s fuera, aún no habla
      correr(a, 15, 5, 115);           // vuelve a zona
      expect(correr(a, 20, 15, 150), isEmpty);   // otros 15 s: sigue sin hablar
    });
  });

  group('cuándo SÍ, y cuántas veces', () {
    test('avisa al pasar de la persistencia, con el número y el rango', () {
      final a = AvisoZona(objetivo: z2, escala: 'fc');
      final dicho = correr(a, 0, AvisoZona.persistenciaSeg + 1, 150);
      expect(dicho.length, 1);
      expect(dicho.first, contains('150'));
      expect(dicho.first, contains('107-125 ppm'));
      expect(dicho.first, contains('Afloja'));     // va pasado
    });

    test('por debajo le dice que puede apretar, no que afloje', () {
      final a = AvisoZona(objetivo: z2, escala: 'fc');
      final dicho = correr(a, 0, AvisoZona.persistenciaSeg + 1, 95);
      expect(dicho.first, contains('apretar'));
      expect(a.estado, EstadoZona.porDebajo);
    });

    test('media hora fuera NO son mil avisos: como mucho el tope', () {
      final a = AvisoZona(objetivo: z2, escala: 'fc');
      final dicho = correr(a, 0, 1800, 150);      // 30 minutos pasado de vueltas
      expect(dicho.length, AvisoZona.maximoAvisos);
    });

    test('entre aviso y aviso se calla lo pactado', () {
      final a = AvisoZona(objetivo: z2, escala: 'fc');
      correr(a, 0, AvisoZona.persistenciaSeg + 1, 150);          // primer aviso
      final s = AvisoZona.persistenciaSeg + 1;
      expect(correr(a, s, AvisoZona.esperaSeg - 5, 150), isEmpty);
      expect(correr(a, s + AvisoZona.esperaSeg, 2, 150).length, 1);
    });

    test('vibra la PRIMERA vez, aunque no toque hablar', () {
      final a = AvisoZona(objetivo: z2, escala: 'fc');
      var vibraciones = 0;
      for (var s = 0; s < 300; s++) {
        if (a.tick(s, 150).vibrar) vibraciones++;
      }
      // Una sola vibración por salida: no un zumbido continuo.
      expect(vibraciones, 1);
    });
  });

  group('el tope es de la SESIÓN, no del bloque', () {
    test('cambiar de bloque no regala más avisos', () {
      var a = AvisoZona(objetivo: z2, escala: 'fc');
      correr(a, 0, 1800, 150);
      expect(a.avisosDados, AvisoZona.maximoAvisos);

      // Bloque nuevo, objetivo nuevo… y el contador sigue donde estaba.
      a = a.paraBloque(objetivo: const RangoFc(desde: 142, hasta: 160), escala: 'fc');
      expect(a.avisosDados, AvisoZona.maximoAvisos);
      expect(correr(a, 1800, 1800, 100), isEmpty);
    });
  });

  group('los límites del rango', () {
    test('el borde exacto está DENTRO', () {
      final a = AvisoZona(objetivo: z2, escala: 'fc');
      expect(a.tick(0, 107).estado, EstadoZona.dentro);
      expect(a.tick(1, 125).estado, EstadoZona.dentro);
      expect(a.tick(2, 126).estado, EstadoZona.porEncima);
      expect(a.tick(3, 106).estado, EstadoZona.porDebajo);
    });

    test('la última zona no tiene techo: no se puede ir "por encima" de ella', () {
      final a = AvisoZona(objetivo: const RangoFc(desde: 160), escala: 'fc');
      expect(a.tick(0, 200).estado, EstadoZona.dentro);
      expect(a.tick(1, 150).estado, EstadoZona.porDebajo);
      expect(const RangoFc(desde: 160).texto, '160+ ppm');
    });
  });
}
