import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ritmooptimo_mobile/screens/session/fuerza_session_screen.dart';

/// "La última vez: 3×10 · 22 kg · hace 6 días".
///
/// ⚠️ ES LO QUE MÁS ENGANCHA de una app de fuerza, y no es decoración: sin él el
/// deportista no sabe si progresa. Levantar 22 kg no significa nada; levantar 22
/// donde la semana pasada levantaste 20, sí.
///
/// ⚠️ Y SIN LA FECHA NO VALE: "3×10 con 22 kg" de hace tres meses no es una
/// referencia, es un recuerdo — y compararse con ella induce a error.
void main() {
  final sesion = {
    'id': 's1', 'title': 'Fuerza',
    'structure': [
      {'block': 'Fuerza', 'tipo': 'series', 'ejercicios': [
        {'slug': 'hip_thrust', 'nombre': 'Hip thrust', 'series': 3, 'reps': 10,
         'carga': {'tipo': 'kg', 'valor': 24}, 'descanso_s': 90},
      ]},
    ],
  };

  Widget app(Map<String, dynamic> historial, {double escala = 1.0}) => ProviderScope(
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
                size: const Size(360, 700), textScaler: TextScaler.linear(escala)),
            child: FuerzaSessionScreen(
              session: sesion,
              cargarHistorial: (_) async => historial,
            ),
          ),
        ),
      );

  testWidgets('enseña qué hizo la última vez, con la fecha', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 700));
    await tester.pumpWidget(app({
      'hip_thrust': {'series': 3, 'reps': 10, 'hace_dias': 6,
                     'carga': {'tipo': 'kg', 'valor': 22}},
    }));
    await tester.pump();
    await tester.pump();
    expect(find.text('La última vez: 3×10  ·  22 kg  ·  hace 6 días'), findsOneWidget);
    // Hoy le piden 24 donde levantó 22: la comparación es el producto.
    expect(find.text('24 kg'), findsOneWidget);
  });

  testWidgets('ayer y hoy se dicen con palabras, no "hace 1 días"', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 700));
    await tester.pumpWidget(app({
      'hip_thrust': {'series': 3, 'reps': 8, 'hace_dias': 1,
                     'carga': {'tipo': 'rir', 'valor': 2}},
    }));
    await tester.pump();
    await tester.pump();
    expect(find.text('La última vez: 3×8  ·  RIR 2  ·  ayer'), findsOneWidget);
  });

  testWidgets('un isométrico se recuerda en segundos, sin carga', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 700));
    await tester.pumpWidget(app({
      'hip_thrust': {'series': 3, 'tiempo_s': 45, 'hace_dias': 4, 'carga': null},
    }));
    await tester.pump();
    await tester.pump();
    expect(find.text('La última vez: 3×45s  ·  hace 4 días'), findsOneWidget);
  });

  testWidgets('SIN historial no se inventa nada: no aparece la línea', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 700));
    await tester.pumpWidget(app(const {}));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('La última vez'), findsNothing);
    expect(find.text('Hip thrust'), findsOneWidget);   // la sesión funciona igual
  });

  testWidgets('con historial, AGUANTA LA LETRA AL 180 %', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 700));
    await tester.pumpWidget(app({
      'hip_thrust': {'series': 3, 'reps': 10, 'hace_dias': 6,
                     'carga': {'tipo': 'kg', 'valor': 22}},
    }, escala: 1.8));
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
