// ============================================================
//  LA TARJETA DE "TU AÑO"
//
//  Teníamos 382 noches del reloj guardadas y ni el deportista ni su entrenador
//  podían verlas. Las demás tarjetas de Bienestar miran ventanas cortas a
//  propósito (7 días, hoy) porque para decidir mañana eso es lo que vale; esta
//  cuenta la historia que esas ventanas no dejan ver.
//
//  ⚠️ LO QUE SE PRUEBA AQUÍ NO SON LOS NÚMEROS. Esos los calcula el servidor y
//  ya están probados allí (35 comprobaciones). Aquí se prueba que la pantalla
//  PINTA LO QUE LE MANDAN Y NADA MÁS: si empezara a decidir por su cuenta —a
//  redondear, a inventarse un tono, a rellenar un hueco— habría dos criterios
//  para la misma historia y acabarían diciendo cosas distintas.
//
//  Y sobre todo: que cuando NO hay nada que contar, la tarjeta DESAPARECE. Una
//  tarjeta vacía o con un error dentro, en una pantalla que va de cómo estás,
//  solo preocupa sin decir nada.
// ============================================================
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ritmooptimo_mobile/core/network/api_client.dart';
import 'package:ritmooptimo_mobile/config/skins/skin_config.dart';
import 'package:ritmooptimo_mobile/providers/skin_provider.dart';
import 'package:ritmooptimo_mobile/widgets/anio_card.dart';

/// Lo que responde el backend de verdad, recortado.
Map<String, dynamic> _anio({
  int meses = 6,
  List<Map<String, dynamic>>? lectura,
}) => {
  'fuente': 'garmin',
  'noches': 382,
  'meses': [
    for (var i = 0; i < meses; i++)
      {
        'mes': '2025-${(8 + i).toString().padLeft(2, '0')}',
        'noches': 30, 'fc': 54 + i, 'hrv': 36 - i, 'sueno': 7.2,
        'pocosDatos': false, 'enCurso': i == meses - 1,
        'minutos': 900, 'sesiones': 20,
      },
  ],
  'lectura': lectura ?? [
    {'tono': 'bien', 'texto': 'Estás por encima de tu año: tu HRV va por 39 ms.'},
    {'tono': 'ojo', 'texto': 'Coméntaselo a tu entrenador.'},
    {'tono': 'info', 'texto': 'Donde mejor dormiste fue en septiembre.'},
  ],
};

class _ApiFalsa extends ApiClient {
  final Map<String, dynamic>? datos;
  final Object? error;
  int llamadas = 0;
  _ApiFalsa({this.datos, this.error});

  @override
  Future<Map<String, dynamic>> getAnio() async {
    llamadas++;
    if (error != null) throw error!;
    return datos!;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<_ApiFalsa> abrir(WidgetTester tester,
      {Map<String, dynamic>? datos, Object? error}) async {
    final api = _ApiFalsa(datos: datos, error: error);
    late SkinConfig skin;
    await tester.pumpWidget(ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api)],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(builder: (_, ref, __) {
            skin = ref.watch(activeSkinProvider);
            return SingleChildScrollView(child: AnioCard(skin: skin));
          }),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return api;
  }

  // ── 1. Pinta lo que le mandan, tal cual ─────────────────────────────
  testWidgets('enseña las frases que manda el servidor, sin retocarlas',
      (tester) async {
    await abrir(tester, datos: _anio());
    expect(find.text('Tu año'), findsOneWidget);
    expect(find.text('382 noches'), findsOneWidget);
    expect(find.text('Estás por encima de tu año: tu HRV va por 39 ms.'),
        findsOneWidget);
    expect(find.text('Coméntaselo a tu entrenador.'), findsOneWidget);
    expect(find.text('Donde mejor dormiste fue en septiembre.'), findsOneWidget);
  });

  testWidgets('cada frase con el icono de su tono', (tester) async {
    await abrir(tester, datos: _anio());
    expect(find.byIcon(Icons.trending_up), findsOneWidget);   // bien
    expect(find.byIcon(Icons.info_outline), findsOneWidget);  // ojo
    expect(find.byIcon(Icons.remove), findsOneWidget);        // info
  });

  // ── 2. ⚠️ SIN NADA QUE CONTAR, DESAPARECE ───────────────────────────
  //
  // Una tarjeta vacía en una pantalla de bienestar parece que algo falla.
  testWidgets('con menos de 3 meses no se pinta nada', (tester) async {
    await abrir(tester, datos: _anio(meses: 2));
    expect(find.text('Tu año'), findsNothing);
  });

  testWidgets('sin lectura tampoco', (tester) async {
    await abrir(tester, datos: _anio(lectura: []));
    expect(find.text('Tu año'), findsNothing);
  });

  testWidgets('y si el servidor falla, DESAPARECE en vez de dar un error',
      (tester) async {
    final api = await abrir(tester, error: DioException(
      requestOptions: RequestOptions(path: '/athlete/anio'),
      response: Response(
        requestOptions: RequestOptions(path: '/athlete/anio'),
        statusCode: 500,
      ),
    ));
    expect(api.llamadas, 1, reason: 'lo intentó');
    expect(find.text('Tu año'), findsNothing);
    expect(find.textContaining('error', findRichText: true), findsNothing,
        reason: 'en una pantalla de cómo estás, un error solo preocupa');
  });

  // ── 3. ⚠️ LA PANTALLA NO DECIDE NADA ────────────────────────────────
  //
  // Si empezara a inventarse frases —un "todo bien" cuando no viene ninguna—
  // habría DOS criterios para la misma historia, y el día que cambiara el del
  // servidor la app seguiría contando el suyo sin que nadie se enterase.
  testWidgets('no se inventa ni una frase que no venga del servidor',
      (tester) async {
    await abrir(tester, datos: _anio(lectura: [
      {'tono': 'info', 'texto': 'Una sola cosa que decir.'},
    ]));
    expect(find.text('Una sola cosa que decir.'), findsOneWidget);
    // Solo esa: ni un consejo de propina.
    expect(find.byIcon(Icons.trending_up), findsNothing);
    expect(find.byIcon(Icons.info_outline), findsNothing);
  });

  // ── 4. Un tono desconocido no rompe la pantalla ─────────────────────
  //
  // El servidor puede añadir tonos mañana; la app es un APK y tardará semanas
  // en actualizarse en el móvil de cada uno. Que se pinte en neutro, no que
  // reviente.
  testWidgets('un tono que no conoce se pinta en neutro, sin romperse',
      (tester) async {
    await abrir(tester, datos: _anio(lectura: [
      {'tono': 'invento_futuro', 'texto': 'Algo nuevo que dirá el servidor.'},
    ]));
    expect(find.text('Algo nuevo que dirá el servidor.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
