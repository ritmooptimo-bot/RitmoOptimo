import 'dart:async';

import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';

/// CADENCIA — pasos por minuto, del contador de pasos del propio móvil.
///
/// Antes no había NINGUNA fuente: `setCurrentCadence` existía, la pantalla sabía
/// pintarla y el backend sabía promediarla, pero no había quien la produjera.
/// Resultado: `cadence_avg_rpm` en blanco en todas las sesiones mientras el
/// Garmin daba 71.
///
/// Se usa el contador de pasos del teléfono (sensor de hardware, gasto de
/// batería mínimo) y no el acelerómetro en bruto: el sistema ya hace la
/// detección de zancada y lo hace mejor.
///
/// El contador devuelve pasos ACUMULADOS DESDE QUE ARRANCÓ EL MÓVIL, no desde
/// que empieza la sesión. Por eso aquí solo se miran diferencias dentro de una
/// ventana móvil; el valor absoluto no significa nada para nosotros.
class CadenceService {
  /// Ventana sobre la que se promedia. Corta de más y la cifra baila con cada
  /// zancada; larga de más y no refleja un cambio de ritmo.
  static const _ventana = Duration(seconds: 20);

  StreamSubscription<StepCount>? _sub;
  final List<({DateTime t, int pasos})> _muestras = [];

  int? _cadenciaActual;
  /// Pasos por minuto ahora mismo. null = todavía sin datos suficientes.
  int? get cadenciaSpm => _cadenciaActual;

  final _controller = StreamController<int>.broadcast();
  Stream<int> get cadenceStream => _controller.stream;

  /// Pide el permiso de actividad física. Devuelve false si el atleta lo niega:
  /// en ese caso NO se inventa cadencia, simplemente no habrá.
  static Future<bool> pedirPermiso() async {
    final estado = await Permission.activityRecognition.request();
    return estado.isGranted;
  }

  /// Arranca la medición. Si no hay permiso o el móvil no tiene contador de
  /// pasos, se queda callado: la sesión sigue igual, solo sin cadencia.
  Future<void> start() async {
    if (_sub != null) return;
    try {
      if (!await pedirPermiso()) return;
      _sub = Pedometer.stepCountStream.listen(
        _onStepCount,
        onError: (_) {
          // Móvil sin sensor de pasos → sin cadencia, y ya está. No es un fallo
          // de la sesión y no debe romper nada.
          _cadenciaActual = null;
        },
        cancelOnError: false,
      );
    } catch (_) {
      _cadenciaActual = null;
    }
  }

  void _onStepCount(StepCount evento) {
    final ahora = DateTime.now();
    _muestras.add((t: ahora, pasos: evento.steps));
    _muestras.removeWhere((m) => ahora.difference(m.t) > _ventana);
    if (_muestras.length < 2) return;

    final primera = _muestras.first, ultima = _muestras.last;
    final seg = ultima.t.difference(primera.t).inMilliseconds / 1000.0;
    final pasos = ultima.pasos - primera.pasos;
    if (seg < 5 || pasos <= 0) return;   // muy poca ventana para fiarse

    final spm = (pasos / seg * 60).round();
    // Fuera de este rango no es correr ni andar: es el sensor confundido.
    if (spm < 30 || spm > 260) return;

    _cadenciaActual = spm;
    if (!_controller.isClosed) _controller.add(spm);
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _muestras.clear();
    _cadenciaActual = null;
  }

  void dispose() {
    stop();
    _controller.close();
  }
}
