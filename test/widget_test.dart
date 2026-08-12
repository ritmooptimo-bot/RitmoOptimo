import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ritmooptimo_mobile/config/router.dart';
import 'package:ritmooptimo_mobile/providers/skin_provider.dart';

/// El arranque: que la app se pueda montar de verdad.
///
/// ⚠️ Llevaba fallando desde que se adoptó Riverpod: era el test de plantilla y
/// pumpeaba `RitmoOptimoApp` a pelo → "Bad state: No ProviderScope found". Un
/// test siempre en rojo no avisa de nada; enseña a no mirar el rojo.
///
/// Se prueba a nivel de contenedor, no pumpeando la app entera: la pantalla de
/// inicio abre temporizadores y sale a la red, y un test que los deja colgando
/// falla por el andamiaje, no por la app. Lo que aquí importa es que el
/// cableado de providers se resuelve y que la primera pantalla es la que toca.
void main() {
  test('el cableado de la app se resuelve y arranca en la pantalla de inicio',
      () {
    final contenedor = ProviderContainer();
    addTearDown(contenedor.dispose);

    final router = contenedor.read(routerProvider);
    expect(router.configuration.routes, isNotEmpty);
    expect(
      router.routeInformationProvider.value.uri.toString(),
      AppRoutes.home,
    );

    // Y el tema: sin piel no hay pantalla que pintar.
    expect(contenedor.read(skinProvider).skin, isNotNull);
  });
}
