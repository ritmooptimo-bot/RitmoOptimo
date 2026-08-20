// ============================================================
//  LA PANTALLA DEL RELOJ DEL DEPORTISTA
//
//  Hasta hoy enlazar el Garmin era cosa del entrenador, desde el panel. Son los
//  datos de salud del deportista: la autorización tiene que ser suya.
//
//  ⚠️ LO QUE MÁS IMPORTA PROBAR:
//
//   1. Que el botón de conectar NO SE PUEDA PULSAR sin autorización. Un
//      interruptor que se puede saltar no es un consentimiento, es un adorno.
//   2. Que los textos que se ven sean los que MANDA EL SERVIDOR, no unos
//      escritos aquí. Lo que se guarda en `medical_consents` tiene que ser
//      exactamente lo que se le enseñó.
//   3. Que un error del servidor se enseñe TAL CUAL. "Algo ha ido mal" cuando
//      el servidor ya ha dicho "revisa el identificador" es esconder la
//      respuesta que resolvía el problema.
// ============================================================
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ritmooptimo_mobile/core/network/api_client.dart';
import 'package:ritmooptimo_mobile/screens/profile/garmin_screen.dart';

// ── Lo que responde el backend de verdad ─────────────────────────────
Map<String, dynamic> _respuesta({
  bool vinculado = false,
  int noches = 0,
  String? desde,
  bool historiaCorta = true,
}) => {
  'estado': {
    'vinculado': vinculado, 'cuenta': vinculado ? 'i664472' : null,
    'noches': noches, 'desde': desde, 'hasta': desde,
    'ultimaRevision': null, 'historiaCorta': historiaCorta,
  },
  'pasos': [
    {'n': 1, 'titulo': 'Conecta tu Garmin a intervals.icu',
     'detalle': 'Entra en intervals.icu y conéctala con Garmin Connect.'},
    {'n': 4, 'titulo': 'Pide tus datos antiguos',
     'detalle': 'IMPORTANTE: intervals.icu solo trae lo nuevo.', 'clave': true},
  ],
  'entra': [
    {'icono': 'sleep', 'titulo': 'Tu sueño', 'detalle': 'Medido toda la noche'},
    {'icono': 'hrv', 'titulo': 'Tu HRV', 'detalle': 'Dice si estás recuperado'},
  ],
  'sale': [
    {'icono': 'watch', 'titulo': 'Tus sesiones, en el reloj',
     'detalle': 'El plan te llega al Garmin'},
  ],
  'consentimiento': {
    'texto': 'Autorizo a RitmoÓptimo a conectarse a mi cuenta de intervals.icu.',
    'version': '1.0',
  },
};

class _ApiFalsa extends ApiClient {
  final Map<String, dynamic> alCargar;
  final Object? errorAlConectar;
  Map<String, dynamic>? ultimoEnvio;

  _ApiFalsa({required this.alCargar, this.errorAlConectar});

  @override
  Future<Map<String, dynamic>> getGarmin() async => alCargar;

  @override
  Future<Map<String, dynamic>> conectarGarmin({
    required String cuenta, required String apiKey, required bool autorizo,
  }) async {
    ultimoEnvio = {'cuenta': cuenta, 'api_key': apiKey, 'autorizo': autorizo};
    if (errorAlConectar != null) throw errorAlConectar!;
    return {'ok': true, 'estado': _respuesta(vinculado: true, noches: 382,
            desde: '2025-08-04', historiaCorta: false)['estado'],
            'bienestar': {'total': 382, 'nuevos': 382}};
  }
}

DioException _errorDelServidor(String mensaje) => DioException(
      requestOptions: RequestOptions(path: '/athlete/garmin'),
      response: Response(
        requestOptions: RequestOptions(path: '/athlete/garmin'),
        statusCode: 400,
        data: {'error': mensaje},
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ⚠️ PANTALLA ALTA A PROPÓSITO. Un `ListView` NO construye lo que queda fuera
  // de la vista, así que en el móvil de 600 px de las pruebas los pasos y los
  // campos ni existían y el test fallaba por algo que no era el fallo. Con la
  // pantalla alta cabe todo y se comprueba lo que se quería comprobar.
  setUp(() {
    final v = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    v.physicalSize = const Size(1000, 4200);
    v.devicePixelRatio = 1.0;
  });
  tearDown(() {
    final v = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    v.resetPhysicalSize();
    v.resetDevicePixelRatio();
  });

  Future<_ApiFalsa> abrir(WidgetTester tester, {
    Map<String, dynamic>? datos,
    Object? errorAlConectar,
  }) async {
    final api = _ApiFalsa(
        alCargar: datos ?? _respuesta(), errorAlConectar: errorAlConectar);
    await tester.pumpWidget(ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api)],
      child: const MaterialApp(home: GarminScreen()),
    ));
    await tester.pumpAndSettle();
    return api;
  }

  // ── 1. LOS TEXTOS VIENEN DEL SERVIDOR ──────────────────────────────
  testWidgets('pinta los pasos y el texto de autorización que manda el servidor',
      (tester) async {
    await abrir(tester);
    expect(find.text('Conecta tu Garmin a intervals.icu'), findsOneWidget);
    expect(find.textContaining('solo trae lo nuevo'), findsOneWidget,
        reason: 'el paso de los datos antiguos es el que nadie adivina');
    expect(
        find.text('Autorizo a RitmoÓptimo a conectarse a mi cuenta de intervals.icu.'),
        findsOneWidget,
        reason: 'tiene que verse EXACTAMENTE el texto que luego se guarda');
    expect(find.text('Tu sueño'), findsOneWidget);
    expect(find.text('Tus sesiones, en el reloj'), findsOneWidget);
  });

  // ── 2. SIN AUTORIZACIÓN NO SE CONECTA ──────────────────────────────
  testWidgets('el botón de conectar NO se puede pulsar sin autorizar',
      (tester) async {
    await abrir(tester);

    // Con los dos campos llenos pero SIN autorizar: sigue apagado.
    await tester.enterText(find.byType(TextField).first, 'i664472');
    await tester.enterText(find.byType(TextField).last, 'clave-larga-de-prueba');
    await tester.pumpAndSettle();

    final boton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Conectar mi reloj'));
    expect(boton.onPressed, isNull,
        reason: 'un interruptor de consentimiento que se puede saltar no vale');
  });

  testWidgets('con autorización y los datos, sí se conecta y viaja el permiso',
      (tester) async {
    final api = await abrir(tester);

    await tester.enterText(find.byType(TextField).first, 'i664472');
    await tester.enterText(find.byType(TextField).last, 'clave-larga-de-prueba');
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    final boton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Conectar mi reloj'));
    expect(boton.onPressed, isNotNull, reason: 'ahora sí debe poder pulsarse');

    await tester.tap(find.widgetWithText(ElevatedButton, 'Conectar mi reloj'));
    await tester.pumpAndSettle();

    expect(api.ultimoEnvio?['autorizo'], isTrue,
        reason: 'la autorización tiene que llegar al servidor, no quedarse aquí');
    expect(api.ultimoEnvio?['cuenta'], 'i664472');
  });

  // ── 3. EL CAMPO SOLO ADMITE EL FORMATO BUENO ───────────────────────
  testWidgets('pegar "Athlete ID: i664472" deja solo el identificador',
      (tester) async {
    await abrir(tester);
    // El caso de verdad: se copia de intervals.icu con la etiqueta pegada
    // delante. Sin el filtro, eso llega al servidor y vuelve rebotado.
    await tester.enterText(find.byType(TextField).first, 'Athlete ID: i664472');
    await tester.pumpAndSettle();
    expect(find.text('i664472'), findsOneWidget,
        reason: 'se limpia al teclear, no después de esperar al servidor');
  });

  // ── 4. YA CONECTADO ────────────────────────────────────────────────
  testWidgets('conectado: dice cuántas noches y desde cuándo, en letra',
      (tester) async {
    await abrir(tester, datos: _respuesta(
        vinculado: true, noches: 382, desde: '2025-08-04', historiaCorta: false));

    expect(find.text('Tu Garmin está conectado'), findsOneWidget);
    expect(find.textContaining('382 noches recibidas'), findsOneWidget);
    expect(find.textContaining('4 de agosto de 2025'), findsOneWidget,
        reason: '"2025-08-04" no se lo dice a nadie');
    expect(find.textContaining('Te falta tu historia'), findsNothing,
        reason: 'con un año no se le pide que descargue nada');
  });

  // ── 5. ⚠️ Y AL REVÉS: HISTORIA CORTA SÍ AVISA ──────────────────────
  //
  // Un aviso que solo se ha visto callado no sirve de nada.
  testWidgets('conectado pero con poca historia: le dice qué tiene que hacer',
      (tester) async {
    await abrir(tester, datos: _respuesta(
        vinculado: true, noches: 12, desde: '2026-08-08', historiaCorta: true));

    expect(find.text('Te falta tu historia'), findsOneWidget);
    expect(find.textContaining('datos antiguos de Garmin'), findsOneWidget);
    expect(find.textContaining('Ya los he pedido'), findsOneWidget,
        reason: 'y un botón para no tener que esperar 24 h');
  });

  // ── 6. EL ERROR DEL SERVIDOR SE ENSEÑA TAL CUAL ────────────────────
  testWidgets('un error del servidor se enseña con SUS palabras',
      (tester) async {
    await abrir(tester,
        errorAlConectar: _errorDelServidor(
            'intervals.icu no ha aceptado esos datos. Revisa que el identificador '
            'y la clave sean los de tu cuenta.'));

    await tester.enterText(find.byType(TextField).first, 'i111111');
    await tester.enterText(find.byType(TextField).last, 'clave-que-no-vale');
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Conectar mi reloj'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Revisa que el identificador'), findsOneWidget,
        reason: 'el servidor ya dijo qué pasaba; taparlo con "algo ha ido mal" '
                'es esconder la respuesta');
  });
}
