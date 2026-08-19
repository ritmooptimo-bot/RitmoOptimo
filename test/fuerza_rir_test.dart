import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ritmooptimo_mobile/screens/session/fuerza_session_screen.dart';

/// La pregunta que hace posible el e1RM: **cuántas te sobraban**.
///
/// ⚠️ LO QUE SE PRUEBA AQUÍ NO ES LA HOJA, ES LA REGLA. Hasta ahora se guardaba
/// el RIR PRESCRITO —le pedimos 2 y anotábamos 2— y estimar un máximo con eso es
/// calcular sobre un número que nadie ha medido. Estas pruebas fijan las tres
/// cosas que no pueden torcerse:
///
///   1. Se pregunta SOLO donde hay e1RM. Preguntarlo en los diez ejercicios de
///      la sesión sería un interrogatorio y se dejaría de contestar.
///   2. Lo que contesta ÉL viaja como `rir_declarado`. Si no contesta, la clave
///      no va — y sin clave el servidor no estima. Silencio, no un 2 inventado.
///   3. Se puede no contestar y seguir entrenando.
void main() {
  Map<String, dynamic> sesion({required bool pideRir}) => {
    'id': 's1',
    'title': 'Fuerza tren inferior',
    'structure': [
      {'block': 'Fuerza máxima', 'min': 30, 'ejercicios': [
        {'slug': 'sentadilla_barra', 'nombre': 'Sentadilla trasera con barra',
         'series': 2, 'reps': 5, 'carga': {'tipo': 'kg', 'valor': 80},
         'descanso_s': 120, 'pide_rir': pideRir},
        {'slug': 'plancha_frontal', 'nombre': 'Plancha frontal',
         'series': 1, 'tiempo_s': 40, 'descanso_s': 45},
      ]},
    ],
  };

  late List<Map<String, dynamic>> guardado;

  Widget app({required bool pideRir, double escala = 1.0}) {
    guardado = [];
    return ProviderScope(
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
              size: const Size(360, 640), textScaler: TextScaler.linear(escala)),
          child: FuerzaSessionScreen(
            session: sesion(pideRir: pideRir),
            cargarHistorial: (_) async => const <String, dynamic>{},
            onFinish: (series) async => guardado = series,
          ),
        ),
      ),
    );
  }

  testWidgets('en un ejercicio CON e1RM pregunta cuántas le sobraban',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    await tester.pumpWidget(app(pideRir: true));
    await tester.pump();

    await tester.tap(find.text('SERIE HECHA'));
    await tester.pumpAndSettle();

    expect(find.textContaining('¿Cuántas repeticiones más'), findsOneWidget);
    // En el idioma del deportista, no "RIR": la palabra técnica en mitad de una
    // serie es la mejor forma de que nadie conteste.
    expect(find.text('Ninguna más'), findsOneWidget);
    expect(find.text('Dos'), findsOneWidget);
    // Y a letra normal se contesta SIN hacer scroll: todo cabe, incluido el
    // "Ahora no". Una pregunta que obliga a rebuscar se deja de contestar.
    expect(find.text('Cuatro o más').hitTestable(), findsOneWidget);
    expect(find.text('Ahora no').hitTestable(), findsOneWidget);
    expect(find.text('Sentadilla trasera con barra'), findsWidgets);
  });

  testWidgets('en un ejercicio SIN e1RM no pregunta nada: toque y a descansar',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    await tester.pumpWidget(app(pideRir: false));
    await tester.pump();

    await tester.tap(find.text('SERIE HECHA'));
    await tester.pumpAndSettle();

    expect(find.textContaining('¿Cuántas repeticiones más'), findsNothing);
    expect(find.text('DESCANSO'), findsOneWidget);
  });

  testWidgets('lo que contesta ÉL viaja como rir_declarado', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    await tester.pumpWidget(app(pideRir: true));
    await tester.pump();

    // Serie 1: dice que le sobraban dos.
    await tester.tap(find.text('SERIE HECHA'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ESTOY LISTO'));
    await tester.pump();

    // Serie 2: ninguna más.
    await tester.tap(find.text('SERIE HECHA'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ninguna más'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ESTOY LISTO'));
    await tester.pump();

    // La plancha no lleva e1RM: ni pregunta, ni aporta el dato. Y va por
    // tiempo, así que se cronometra en vez de darse por hecha de un toque.
    await tester.tap(find.text('EMPEZAR'));
    await tester.pump();
    for (var i = 0; i < 41; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pumpAndSettle();
    await tester.tap(find.text('GUARDAR'));
    await tester.pumpAndSettle();

    expect(guardado.length, 3);
    expect(guardado[0]['rir_declarado'], 2);
    expect(guardado[1]['rir_declarado'], 0);   // 0 es un dato, no un "no contestó"
    expect(guardado[2].containsKey('rir_declarado'), isFalse);
    // Y la carga sigue viajando con su tipo: 80 kg no es un 80 a secas.
    expect(guardado[0]['carga'], {'tipo': 'kg', 'valor': 80});
  });

  testWidgets('puede no contestar: la serie cuenta igual y NO se inventa un RIR',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    await tester.pumpWidget(app(pideRir: true));
    await tester.pump();

    await tester.tap(find.text('SERIE HECHA'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ahora no'));
    await tester.pumpAndSettle();

    expect(find.text('DESCANSO'), findsOneWidget);      // sigue entrenando
    await tester.tap(find.text('ESTOY LISTO'));
    await tester.pump();
    expect(find.text('Serie 2 de 2'), findsOneWidget);  // la serie contó
  });

  testWidgets('cerrar la hoja por fuera tampoco inventa un RIR', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    await tester.pumpWidget(app(pideRir: true));
    await tester.pump();

    await tester.tap(find.text('SERIE HECHA'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(180, 20));          // fuera de la hoja
    await tester.pumpAndSettle();

    expect(find.text('DESCANSO'), findsOneWidget);
    await tester.tap(find.text('ESTOY LISTO'));
    await tester.pump();
    await tester.tap(find.text('SERIE HECHA'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ahora no'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ESTOY LISTO'));
    await tester.pump();
    // ⚠️ La plancha va POR TIEMPO: ahora se cronometra en vez de darse por
    // hecha de un toque. Antes decía «SERIE HECHA» y había que contar los 40
    // segundos de cabeza, aguantando la plancha.
    await tester.tap(find.text('EMPEZAR'));             // plancha, 40 s
    await tester.pump();
    for (var i = 0; i < 41; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pumpAndSettle();
    await tester.tap(find.text('GUARDAR'));
    await tester.pumpAndSettle();

    expect(guardado.length, 3);
    expect(guardado.any((s) => s.containsKey('rir_declarado')), isFalse);
  });

  testWidgets('AGUANTA LA LETRA AL 180 %: las cinco opciones son alcanzables',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    await tester.pumpWidget(app(pideRir: true, escala: 1.8));
    await tester.pump();
    expect(tester.takeException(), isNull);             // ningún overflow

    // A esta letra el botón cae bajo el pliegue: el deportista baja hasta él.
    // (Si esto se saltara, el toque se iría al vacío y el test pasaría en falso
    // sin haber abierto nada.)
    await tester.ensureVisible(find.text('SERIE HECHA'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SERIE HECHA'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hoja_rir')), findsOneWidget);   // se abrió

    // La última opción es la que se recortaría en silencio si la hoja fuera un
    // Column: hay que poder llegar hasta ella y pulsarla.
    // Ojo: la última opción ni siquiera EXISTE hasta que se hace scroll — un
    // ListView construye perezosamente. Por eso no vale `ensureVisible`.
    await tester.scrollUntilVisible(find.text('Cuatro o más'), 60,
        scrollable: find.descendant(
            of: find.byKey(const Key('hoja_rir')),
            matching: find.byType(Scrollable)));
    await tester.tap(find.text('Cuatro o más'));
    await tester.pumpAndSettle();

    expect(find.text('DESCANSO'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
