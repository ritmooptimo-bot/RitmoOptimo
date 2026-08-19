// ============================================================
//  EL TOPE DE BÚSQUEDAS DE ANDROID
//
//  Android permite 5 búsquedas BLE cada 30 segundos por aplicación. Pasado ese
//  tope NO devuelve un error: deja de encontrar dispositivos y se calla. Desde
//  fuera parece que la banda se ha estropeado, y lo único que parece arreglarlo
//  es apagar y encender el Bluetooth — porque eso reinicia el contador.
//
//  Va en su propia clase, sin Bluetooth ni Flutter dentro, por un motivo muy
//  concreto: así se puede PROBAR. Un límite que no se ha visto saltar en un
//  test no es un límite, es una intención.
// ============================================================

class LimiteBusquedas {
  final int      maximo;
  final Duration ventana;
  final List<DateTime> _arranques = [];

  LimiteBusquedas({this.maximo = 5, this.ventana = const Duration(seconds: 30)});

  /// Cuánto falta para poder buscar. `Duration.zero` = ya se puede.
  ///
  /// `ahora` se pasa a propósito en vez de leer el reloj aquí dentro: es lo que
  /// permite probar los bordes sin esperar treinta segundos de verdad.
  Duration espera(DateTime ahora) {
    _arranques.removeWhere((t) => ahora.difference(t) >= ventana);
    if (_arranques.length < maximo) return Duration.zero;
    final falta = ventana - ahora.difference(_arranques.first);
    return falta.isNegative ? Duration.zero : falta;
  }

  /// Apunta que se acaba de arrancar una búsqueda.
  void anota(DateTime ahora) => _arranques.add(ahora);

  int get enVentana => _arranques.length;
}
