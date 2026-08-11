import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ritmooptimo_mobile/screens/session/fuerza_session_screen.dart';

/// ⚠️ ESTA PANTALLA ES LA MÁS DIFÍCIL DEL PROYECTO A LETRA DEL 180 %: muchos
/// números y poco sitio. Y un `Column` que no cabe RECORTA sin avisar — el
/// analizador calla y en pantalla grande se ve perfecto. Por eso se prueba a esa
/// escala, que es la real del móvil de pruebas.
void main() {
  final sesion = {
    'id': 's1',
    'title': 'Fuerza tren superior y estiramientos',
    'structure': [
      {'block': 'Fuerza general', 'min': 25, 'tipo': 'circuito', 'rondas': 3,
       'descanso_entre_rondas_s': 90,
       'ejercicios': [
         {'slug': 'sentadilla_goblet', 'nombre': 'Sentadilla goblet',
          'series': 3, 'reps': 10, 'carga': {'tipo': 'rir', 'valor': 2},
          'descanso_s': 45, 'nota': 'Peso pegado al pecho, codos dentro de las rodillas.'},
         {'slug': 'plancha_lateral', 'nombre': 'Plancha lateral',
          'series': 3, 'tiempo_s': 40, 'descanso_s': 45},
       ]},
    ],
  };

  const historial = <String, dynamic>{};

  Widget app({double escala = 1.0, Size tam = const Size(360, 640)}) =>
      ProviderScope(
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: tam, textScaler: TextScaler.linear(escala)),
            child: FuerzaSessionScreen(
              session: sesion,
              // Sin red en las pruebas: el historial se inyecta.
              cargarHistorial: (_) async => historial,
            ),
          ),
        ),
      );

  testWidgets('enseña el ejercicio, la serie y el objetivo con su unidad',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    await tester.pumpWidget(app());
    await tester.pump();

    expect(find.text('Sentadilla goblet'), findsOneWidget);
    expect(find.text('Serie 1 de 3  ·  Ronda 1 de 3'), findsOneWidget);
    expect(find.text('10 reps'), findsOneWidget);
    expect(find.text('RIR 2'), findsOneWidget);            // carga CON su unidad
    expect(find.textContaining('Después:'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AGUANTA LA LETRA AL 180 %', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    await tester.pumpWidget(app(escala: 1.8));
    await tester.pump();
    expect(tester.takeException(), isNull);     // ningún overflow
    expect(find.text('Sentadilla goblet'), findsOneWidget);
  });

  testWidgets('al dar la serie por hecha, entra el DESCANSO con lo siguiente',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    await tester.pumpWidget(app());
    await tester.pump();

    await tester.tap(find.text('SERIE HECHA'));
    await tester.pump();

    expect(find.text('DESCANSO'), findsOneWidget);
    expect(find.text('45 s'), findsOneWidget);              // el corto, no el de ronda
    expect(find.text('AHORA VIENE'), findsOneWidget);
    expect(find.text('Plancha lateral'), findsOneWidget);
    expect(find.text('40 s'), findsOneWidget);              // isométrico: segundos
    expect(tester.takeException(), isNull);
  });

  testWidgets('el descanso corre y se puede saltar', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    await tester.pumpWidget(app());
    await tester.pump();
    await tester.tap(find.text('SERIE HECHA'));
    await tester.pump();

    await tester.pump(const Duration(seconds: 3));
    expect(find.text('42 s'), findsOneWidget);              // ha bajado

    await tester.tap(find.text('ESTOY LISTO'));
    await tester.pump();
    expect(find.text('DESCANSO'), findsNothing);
    expect(find.text('Plancha lateral'), findsOneWidget);   // ya toca el siguiente
  });

  testWidgets('tras la ÚLTIMA serie no hay descanso: se termina', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 900));
    await tester.pumpWidget(app(tam: const Size(360, 900)));
    await tester.pump();

    // 3 rondas × 2 ejercicios = 6 series
    for (var i = 0; i < 6; i++) {
      await tester.tap(find.text('SERIE HECHA'));
      await tester.pump();
      if (find.text('ESTOY LISTO').evaluate().isNotEmpty) {
        await tester.tap(find.text('ESTOY LISTO'));
        await tester.pump();
      }
    }
    expect(find.text('Sesión completada'), findsOneWidget);
    expect(find.textContaining('6 series registradas'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

