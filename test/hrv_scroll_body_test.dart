import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ritmooptimo_mobile/core/hrv/hrv_scroll_body.dart';

/// El fallo real: al medir con la banda y salir la señal sucia, el aviso pasa de
/// una línea a cinco y empujaba fuera de pantalla los botones de USAR VALORES y
/// Repetir — justo los que hacen falta cuando la medición sale mal.
///
/// La trampa es que **un `Column` que no cabe recorta sin avisar**: el
/// analizador calla, en pantalla grande se ve bien, y el fallo solo aparece en
/// el móvil de quien está midiendo. Un test es la única forma de fijarlo.
void main() {
  // Contenido típico de la pantalla con el aviso largo, en un móvil pequeño.
  Widget pantalla({required double alto, double escalaLetra = 1.0}) =>
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(360, alto),
            textScaler: TextScaler.linear(escalaLetra),
          ),
          child: Scaffold(
            body: HrvScrollBody(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, size: 64),
                  const Text('Medición lista',
                      style: TextStyle(fontSize: 22)),
                  const SizedBox(height: 18),
                  const Text(
                    '“Señal ruidosa” = tu banda manda algunos latidos con error. '
                    'Los corregimos, así que este HRV es una ESTIMACIÓN (no '
                    'exacto). Te vale para ver TU tendencia día a día con esta '
                    'misma banda. Para un valor preciso: Polar H10 o Garmin HRM.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                        onPressed: () {}, child: const Text('USAR VALORES')),
                  ),
                  TextButton(onPressed: () {}, child: const Text('Repetir')),
                ],
              ),
            ),
          ),
        ),
      );

  testWidgets('con el aviso largo se llega a USAR VALORES y a Repetir',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 560));
    await tester.pumpWidget(pantalla(alto: 560));

    // Si el contenido se saliera, Flutter habría lanzado el overflow aquí.
    expect(tester.takeException(), isNull);

    // Y los dos botones tienen que ser ALCANZABLES: se llega a ellos rodando.
    await tester.dragUntilVisible(
      find.text('Repetir'),
      find.byType(SingleChildScrollView),
      const Offset(0, -80),
    );
    expect(find.text('Repetir'), findsOneWidget);
    expect(find.text('USAR VALORES'), findsOneWidget);
  });

  testWidgets('aguanta la letra del sistema al 180 %', (tester) async {
    // Es la configuración REAL del móvil de pruebas y explica casi todos los
    // "está feo" del proyecto: a esta escala el texto ocupa casi el doble.
    await tester.binding.setSurfaceSize(const Size(360, 560));
    await tester.pumpWidget(pantalla(alto: 560, escalaLetra: 1.8));
    expect(tester.takeException(), isNull);

    await tester.dragUntilVisible(
      find.text('Repetir'),
      find.byType(SingleChildScrollView),
      const Offset(0, -80),
    );
    expect(find.text('Repetir'), findsOneWidget);
  });

  testWidgets('cuando el contenido cabe de sobra, sigue centrado',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 1400));
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(360, 1400)),
        child: const Scaffold(
          body: HrvScrollBody(child: Text('corto')),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);

    // El centro del texto debe caer cerca del centro de la pantalla: si el
    // scroll hubiera roto el centrado, se pegaría arriba del todo.
    final centro = tester.getCenter(find.text('corto'));
    expect((centro.dy - 700).abs() < 60, isTrue,
        reason: 'el contenido corto debería seguir centrado, y está en $centro');
  });
}
