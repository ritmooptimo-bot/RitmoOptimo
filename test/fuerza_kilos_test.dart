import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ritmooptimo_mobile/models/ejercicio.dart';
import 'package:ritmooptimo_mobile/screens/session/fuerza_session_screen.dart';

/// El peso en la barra, y la guía que impide leerlo como una orden.
///
/// ⚠️ LO QUE SE PROTEGE AQUÍ es que el kilo NUNCA viaje solo. El peso sale de
/// un e1RM estimado hace semanas: no sabe que hoy has dormido cinco horas. El
/// RIR sí. Si la app enseña «90 kg» a secas, alguien hará la última repetición
/// con la espalda antes que quedarse corto.
void main() {
  group('el modelo', () {
    test('lee el RIR guía que acompaña a los kilos', () {
      final e = Ejercicio.fromJson({
        'slug': 'sentadilla_barra', 'series': 4, 'reps': 5,
        'carga': {'tipo': 'kg', 'valor': 90, 'rir_guia': 2,
                  'origen': {'porcentaje': 81.1, 'e1rm_kg': 112.5}},
      });
      expect(e.carga, '90 kg');
      expect(e.guia, 'deja 2 en recámara');
    });

    test('un RIR a secas NO lleva guía: sería decir dos veces lo mismo', () {
      final e = Ejercicio.fromJson({
        'slug': 'prensa_piernas', 'series': 3, 'reps': 10,
        'carga': {'tipo': 'rir', 'valor': 2},
      });
      expect(e.carga, 'RIR 2');
      expect(e.guia, isNull);
    });

    test('RIR guía 0 se dice en cristiano, no como un cero', () {
      final e = Ejercicio.fromJson({
        'slug': 'peso_muerto_convencional', 'series': 3, 'reps': 3,
        'carga': {'tipo': 'kg', 'valor': 120, 'rir_guia': 0},
      });
      expect(e.guia, 'hasta donde llegues');
    });

    test('unos kilos escritos a mano por el entrenador no inventan guía', () {
      final e = Ejercicio.fromJson({
        'slug': 'sentadilla_bulgara', 'series': 3, 'reps': 8,
        'carga': {'tipo': 'kg', 'valor': 12},
      });
      expect(e.carga, '12 kg');
      expect(e.guia, isNull);
    });
  });

  group('la pantalla', () {
    Widget app({required Map<String, dynamic> carga, double escala = 1.0}) =>
        ProviderScope(
          child: MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(size: const Size(360, 640),
                  textScaler: TextScaler.linear(escala)),
              child: FuerzaSessionScreen(
                session: {
                  'id': 's1', 'title': 'Fuerza máxima',
                  'structure': [
                    {'block': 'Fuerza máxima', 'min': 35, 'ejercicios': [
                      {'slug': 'sentadilla_barra',
                       'nombre': 'Sentadilla trasera con barra',
                       'series': 4, 'reps': 5, 'descanso_s': 180,
                       'carga': carga, 'pide_rir': true},
                    ]},
                  ],
                },
                cargarHistorial: (_) async => const <String, dynamic>{},
              ),
            ),
          ),
        );

    testWidgets('enseña los kilos Y la guía, nunca el kilo solo',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      await tester.pumpWidget(app(
          carga: {'tipo': 'kg', 'valor': 90, 'rir_guia': 2}));
      await tester.pump();

      expect(find.text('90 kg'), findsOneWidget);
      expect(find.text('deja 2 en recámara'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sin e1RM se prescribe por esfuerzo y no aparece ningún kilo',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      await tester.pumpWidget(app(carga: {'tipo': 'rir', 'valor': 2}));
      await tester.pump();

      expect(find.text('RIR 2'), findsOneWidget);
      expect(find.textContaining('kg'), findsNothing);
      expect(find.textContaining('recámara'), findsNothing);
    });

    testWidgets('AGUANTA LA LETRA AL 180 % con las dos líneas',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      await tester.pumpWidget(app(
          carga: {'tipo': 'kg', 'valor': 92.5, 'rir_guia': 2}, escala: 1.8));
      await tester.pump();

      expect(tester.takeException(), isNull);       // ningún overflow
      expect(find.text('92.5 kg'), findsOneWidget);
      expect(find.text('deja 2 en recámara'), findsOneWidget);
    });
  });
}
