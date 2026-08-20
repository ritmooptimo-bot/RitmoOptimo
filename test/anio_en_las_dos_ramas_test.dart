// ============================================================
//  "TU AÑO" TIENE QUE ESTAR EN LAS DOS RAMAS
//
//  ⚠️ EL FALLO, CAZADO ABRIENDO LA APP EN EL MÓVIL. La pantalla de Bienestar
//  tiene DOS ramas:
//
//     · el FORMULARIO del check-in, mientras no lo has rellenado
//     · la FICHA de solo lectura, que es la que se ve el resto del día en
//       cuanto lo rellenas
//
//  La tarjeta del año se puso solo en la del formulario. O sea que quien hace
//  su check-in a diario —que es justo el que debe— no la vería NUNCA. La
//  pantalla se veía perfecta; simplemente no estaba.
//
//  Es el fallo de todo el día: LA REGLA EXISTE EN UN CAMINO Y NO EN EL OTRO.
//  No da error, no da aviso; da una pantalla que parece completa.
//
//  Por eso este test abre LAS DOS y busca la tarjeta en ambas.
// ============================================================
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ritmooptimo_mobile/core/network/api_client.dart';
import 'package:ritmooptimo_mobile/screens/wellness/wellness_screen.dart';
import 'package:ritmooptimo_mobile/widgets/anio_card.dart';

class _ApiFalsa extends ApiClient {
  final bool hechoHoy;
  _ApiFalsa({required this.hechoHoy});

  @override
  Future<Map<String, dynamic>> getWellnessToday() async => hechoHoy
      ? {
          'doneToday': true, 'label': 'Día normal',
          'fatigue': 2, 'mood': 4, 'motivation': 4,
          'sleep_hours': 7, 'sleep_quality': 3,
          'hrv_ms': 15, 'resting_hr_bpm': 71,
        }
      : {'doneToday': false};

  @override
  Future<Map<String, dynamic>> getAnio() async => {
        'noches': 382,
        'meses': [
          for (var i = 0; i < 6; i++)
            {
              'mes': '2025-0${8 + i > 9 ? 9 : 8 + i}',
              'noches': 30, 'fc': 54, 'hrv': 36 - i, 'sueno': 7.2,
              'pocosDatos': false, 'enCurso': false,
            },
        ],
        'lectura': [
          {'tono': 'bien', 'texto': 'Estás por encima de tu año.'},
        ],
      };

  // Lo que piden las otras tarjetas, en silencio.
  @override
  Future<Map<String, dynamic>> getReadiness() async => {};
  @override
  Future<Map<String, dynamic>> getHrvBaseline() async => {'status': 'no_data'};
  @override
  Future<Map<String, dynamic>> getProfileBasics() async => {};
  @override
  Future<Map<String, dynamic>> getVo2max() async => {};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Pantalla alta: un ListView no construye lo que queda fuera de la vista, y
  // en el móvil de 600 px de las pruebas la tarjeta ni existiría — el test
  // fallaría por algo que no es el fallo.
  setUp(() {
    final v = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    v.physicalSize = const Size(1000, 5000);
    v.devicePixelRatio = 1.0;
  });
  tearDown(() {
    final v = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    v.resetPhysicalSize();
    v.resetDevicePixelRatio();
  });

  Future<void> abrir(WidgetTester tester, {required bool hechoHoy}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(_ApiFalsa(hechoHoy: hechoHoy))],
      child: const MaterialApp(home: WellnessScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('con el check-in SIN hacer, "Tu año" está', (tester) async {
    await abrir(tester, hechoHoy: false);
    expect(find.byType(AnioCard), findsOneWidget);
    expect(find.text('Tu año'), findsOneWidget);
  });

  testWidgets('⚠️ y con el check-in YA HECHO, TAMBIÉN', (tester) async {
    await abrir(tester, hechoHoy: true);
    // Se comprueba primero que de verdad estamos en la otra rama, o el test
    // podría pasar mirando la pantalla equivocada.
    expect(find.text('Tu check-in de hoy'), findsOneWidget,
        reason: 'esta es la ficha de solo lectura, la otra rama');
    expect(find.byType(AnioCard), findsOneWidget,
        reason: 'quien hace su check-in a diario tiene que poder ver su año');
    expect(find.text('Tu año'), findsOneWidget);
  });

  testWidgets('y en las dos dice lo mismo', (tester) async {
    await abrir(tester, hechoHoy: false);
    expect(find.text('Estás por encima de tu año.'), findsOneWidget);
    await abrir(tester, hechoHoy: true);
    expect(find.text('Estás por encima de tu año.'), findsOneWidget);
  });
}
