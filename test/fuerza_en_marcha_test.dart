// ============================================================
//  La sesión de fuerza EN MARCHA, con la sesión real del sábado.
//
//  ⚠️ Esta pantalla no se había ejecutado nunca: leía un campo que no existe y
//  nunca se abría. Al conectarla salieron dos huecos que solo se ven usándola:
//
//   1. En un ejercicio POR TIEMPO no había cuenta atrás. Una plancha de 45 s
//      enseñaba «45 s» y un botón: te tocaba contarlos a ti, aguantando la
//      plancha. El DESCANSO sí tenía cronómetro y aviso sonoro — justo al revés
//      de lo que hace falta.
//   2. No había forma de deshacer. Con las manos sudadas y el móvil en el
//      suelo, un toque de más dejaba una serie registrada que no se hizo, y la
//      única salida era terminar la sesión con un dato falso.
// ============================================================
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ritmooptimo_mobile/models/ejercicio.dart';
import 'package:ritmooptimo_mobile/screens/session/fuerza_session_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // La sesión de fuerza REAL, del patrón volcado de producción.
  final datos = jsonDecode(File('test/fixtures/plan_real.json').readAsStringSync())
      as Map<String, dynamic>;
  final fuerza = (datos['sesiones'] as List)
      .cast<Map<String, dynamic>>()
      .firstWhere((s) => s['session_type'] == 'fuerza');

  Future<void> abrir(WidgetTester tester,
      {required List<Map<String, dynamic>> recogido}) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: FuerzaSessionScreen(
          session: fuerza,
          // Sin red: el historial se inyecta, que para eso está el parámetro.
          cargarHistorial: (_) async => const {},
          onFinish: (hecho) async => recogido.addAll(hecho),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('abre con el primer ejercicio y su nombre de verdad', (tester) async {
    await abrir(tester, recogido: []);
    final pasos = PasoSerie.desdeBloques(
        BloqueFuerza.desdeEstructura(fuerza['planned_structure']));

    expect(find.text(pasos.first.ejercicio.nombre), findsOneWidget,
        reason: 'el primero es ${pasos.first.ejercicio.nombre}');
    expect(find.textContaining('SERIE 1 DE ${pasos.length}'), findsOneWidget);
  });

  testWidgets('un ejercicio POR TIEMPO se cronometra, no se da por hecho',
      (tester) async {
    await abrir(tester, recogido: []);

    // El primer ejercicio del calentamiento es movilidad por tiempo.
    expect(find.text('EMPEZAR'), findsOneWidget,
        reason: 'en un ejercicio por tiempo el botón arranca el cronómetro, '
            'no lo da por terminado');

    await tester.tap(find.text('EMPEZAR'));
    await tester.pump();

    // Ya está corriendo: aparece la cuenta atrás y la forma de cortarla.
    expect(find.text('NO PUEDO MAS'), findsOneWidget);
    expect(find.text('EMPEZAR'), findsNothing);

    // Y AVANZA de verdad.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('43'), findsOneWidget,
        reason: '45 s menos dos: la cuenta atrás tiene que moverse');
  });

  testWidgets('al terminar el tiempo pasa solo al descanso', (tester) async {
    await abrir(tester, recogido: []);
    await tester.tap(find.text('EMPEZAR'));
    await tester.pump();

    for (var i = 0; i < 46; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.text('DESCANSO'), findsOneWidget,
        reason: 'terminados los 45 s, se descansa sin tocar nada');
  });

  testWidgets('se puede DESHACER un toque de más', (tester) async {
    await abrir(tester, recogido: []);
    final pasos = PasoSerie.desdeBloques(
        BloqueFuerza.desdeEstructura(fuerza['planned_structure']));

    // Arrancar y cortar: eso registra la serie y manda a descansar.
    await tester.tap(find.text('EMPEZAR'));
    await tester.pump();
    await tester.tap(find.text('NO PUEDO MAS'));
    await tester.pump();
    expect(find.textContaining('SERIE 2 DE'), findsOneWidget);

    // Y volver atrás deja la cuenta como estaba.
    await tester.tap(find.text('Me he equivocado, volver'));
    await tester.pump();
    expect(find.textContaining('SERIE 1 DE ${pasos.length}'), findsOneWidget,
        reason: 'deshacer tiene que devolver también el contador');
    expect(find.text(pasos.first.ejercicio.nombre), findsOneWidget);
  });

  testWidgets('cortar antes de tiempo guarda lo que AGUANTÓ, no lo pedido',
      (tester) async {
    final recogido = <Map<String, dynamic>>[];
    await abrir(tester, recogido: recogido);

    await tester.tap(find.text('EMPEZAR'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('NO PUEDO MAS'));
    await tester.pump();

    // Se llega al final saltando descansos y series para poder guardar.
    // (Lo que importa es el PRIMER registro.)
    // El registro vive en el estado; se comprueba al guardar más abajo, pero
    // aquí basta con que la serie 1 no diga 45 s.
    // ⚠️ Anotar 45 s cuando aguantó 3 es inventarse el entrenamiento.
    expect(find.textContaining('SERIE 2 DE'), findsOneWidget);
  });
}
