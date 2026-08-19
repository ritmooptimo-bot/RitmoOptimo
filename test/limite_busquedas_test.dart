// El tope de búsquedas de Android, probado. Sin esto sería una intención.
import 'package:flutter_test/flutter_test.dart';
import 'package:ritmooptimo_mobile/core/ble/limite_busquedas.dart';

void main() {
  final t0 = DateTime(2026, 8, 19, 20, 0, 0);

  test('las cinco primeras pasan', () {
    final l = LimiteBusquedas();
    for (var i = 0; i < 5; i++) {
      final ahora = t0.add(Duration(seconds: i));
      expect(l.espera(ahora), Duration.zero, reason: 'la búsqueda ${i + 1} debería pasar');
      l.anota(ahora);
    }
    expect(l.enVentana, 5);
  });

  test('la SEXTA en menos de 30 s se frena, y dice cuánto falta', () {
    final l = LimiteBusquedas();
    for (var i = 0; i < 5; i++) {
      final ahora = t0.add(Duration(seconds: i));
      l.espera(ahora);
      l.anota(ahora);
    }
    // 10 s después de la primera: quedan 20 para que salga de la ventana.
    final espera = l.espera(t0.add(const Duration(seconds: 10)));
    expect(espera, greaterThan(Duration.zero));
    expect(espera.inSeconds, 20);
  });

  test('pasada la ventana vuelve a dejar buscar', () {
    final l = LimiteBusquedas();
    for (var i = 0; i < 5; i++) {
      final ahora = t0.add(Duration(seconds: i));
      l.espera(ahora);
      l.anota(ahora);
    }
    expect(l.espera(t0.add(const Duration(seconds: 29))), greaterThan(Duration.zero),
        reason: 'a los 29 s la primera sigue dentro de la ventana');
    expect(l.espera(t0.add(const Duration(seconds: 35))), Duration.zero,
        reason: 'a los 35 s ya han caducado todas');
    expect(l.enVentana, 0, reason: 'y la ventana se ha vaciado sola');
  });

  test('una ráfaga larga NO se queda bloqueada para siempre', () {
    // El caso real: le das a Repetir diez veces seguidas, muy rápido.
    final l = LimiteBusquedas();
    for (var i = 0; i < 10; i++) {
      final ahora = t0.add(Duration(milliseconds: i * 200));
      if (l.espera(ahora) == Duration.zero) l.anota(ahora);
    }
    expect(l.enVentana, 5, reason: 'solo cinco llegaron a arrancar de verdad');
    expect(l.espera(t0.add(const Duration(seconds: 31))), Duration.zero,
        reason: 'medio minuto después vuelve a funcionar sin tocar nada');
  });

  test('el tope se puede probar AL REVÉS: sin límite, las diez pasarían', () {
    // Si este test se pusiera verde con el límite puesto, es que el límite no
    // está haciendo nada. Con maximo enorme, las diez arrancan.
    final sinLimite = LimiteBusquedas(maximo: 1000);
    var arrancadas = 0;
    for (var i = 0; i < 10; i++) {
      final ahora = t0.add(Duration(milliseconds: i * 200));
      if (sinLimite.espera(ahora) == Duration.zero) { sinLimite.anota(ahora); arrancadas++; }
    }
    expect(arrancadas, 10);
  });
}
