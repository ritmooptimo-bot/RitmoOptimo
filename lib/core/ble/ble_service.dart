import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'limite_busquedas.dart';

const _hrServiceUuid     = "0000180d-0000-1000-8000-00805f9b34fb";
const _hrMeasurementUuid = "00002a37-0000-1000-8000-00805f9b34fb";

// ⚠️ EL LÍMITE DE ANDROID QUE EXPLICA "APAGA Y ENCIENDE EL BLUETOOTH".
//
// Android permite **5 búsquedas cada 30 segundos** por aplicación. A partir de
// ahí NO da error: deja de devolver resultados y se calla. Desde fuera parece
// que la banda ha desaparecido o que el Bluetooth se ha estropeado, y lo único
// que parece arreglarlo es apagar y encender el Bluetooth — porque eso resetea
// el contador del sistema.
//
// Y esta pantalla lo pisaba con una facilidad enorme: busca al entrar, busca al
// pulsar "Repetir", busca al pulsar "Ver todos", y vuelve a buscar cada vez que
// se entra otra vez. Cinco en medio minuto es de lo más normal.
//
// Así que el tope se lleva AQUÍ, y cuando se llega se dice por qué y cuánto
// falta, en vez de dejar al deportista mirando una lista vacía.
const _maxBusquedas   = 5;
const _ventanaLimite  = Duration(seconds: 30);

/// Lo que pasó al intentar buscar. `espera` solo viene en `throttled`.
class ResultadoBusqueda {
  final bool     arrancada;
  final Duration espera;
  final String?  error;
  const ResultadoBusqueda.ok()             : arrancada = true,  espera = Duration.zero, error = null;
  const ResultadoBusqueda.throttled(this.espera) : arrancada = false, error = null;
  const ResultadoBusqueda.fallo(this.error): arrancada = false, espera = Duration.zero;
}

class BleService {
  BluetoothDevice?    _device;
  StreamSubscription? _hrSub;
  StreamSubscription? _stateSub;

  final _hrController    = StreamController<int>.broadcast();
  final _rrController    = StreamController<List<double>>.broadcast();
  final _stateController = StreamController<bool>.broadcast();

  Stream<int>          get hrStream        => _hrController.stream;
  Stream<List<double>> get rrStream        => _rrController.stream;
  Stream<bool>         get connectedStream => _stateController.stream;

  bool    get isConnected         => _device?.isConnected ?? false;
  String? get connectedDeviceName => _device?.platformName;

  // ── BÚSQUEDA ──────────────────────────────────────────────────────────
  //
  // Scan filtrado por Heart Rate Service UUID (0x180D) durante 20 s.
  // 20 s son necesarios para bandas Garmin (la HRM-Pro Plus tarda en anunciar
  // BLE cuando además está transmitiendo ANT+ a un reloj emparejado).
  Stream<List<ScanResult>> get resultados => FlutterBluePlus.scanResults;
  Stream<bool>             get buscando   => FlutterBluePlus.isScanning;

  final _limite = LimiteBusquedas(maximo: _maxBusquedas, ventana: _ventanaLimite);

  /// Cuánto hay que esperar para que Android acepte otra búsqueda.
  /// `Duration.zero` = se puede buscar ya.
  Duration esperaNecesaria() => _limite.espera(DateTime.now());

  /// Arranca una búsqueda. `ampliada` = todos los dispositivos BLE, no solo los
  /// que anuncian frecuencia cardíaca.
  ///
  /// ⚠️ ANTES ESTO NO SE ESPERABA (`FlutterBluePlus.startScan(...)` a pelo, sin
  /// `await` y sin `try`). Si fallaba —y falla a menudo: búsqueda ya en curso,
  /// permisos, adaptador ocupado— el error se perdía como excepción asíncrona
  /// sin dueño: ni mensaje, ni log, ni pista. La pantalla se quedaba con la
  /// ruedecita girando veinte segundos y luego "Ningún sensor encontrado".
  Future<ResultadoBusqueda> buscar({bool ampliada = false}) async {
    final espera = esperaNecesaria();
    if (espera > Duration.zero) return ResultadoBusqueda.throttled(espera);

    try {
      // Parar la anterior SIEMPRE. Arrancar una búsqueda con otra viva da
      // "Another scan is already in progress" y no arranca ninguna.
      await FlutterBluePlus.stopScan();
      _limite.anota(DateTime.now());
      await FlutterBluePlus.startScan(
        withServices: ampliada ? [] : [Guid(_hrServiceUuid)],
        timeout: const Duration(seconds: 20),
        // Sin esto la lista solo CRECE: un dispositivo que ya no está sigue
        // apareciendo, con su potencia de hace veinte segundos. Es la mitad de
        // "la encuentra pero no es la correcta" — se elige una banda que ya no
        // está a tiro, o la de un vecino que pasó por delante hace un rato.
        continuousUpdates: true,
        removeIfGone: const Duration(seconds: 6),
      );
      return const ResultadoBusqueda.ok();
    } catch (e) {
      return ResultadoBusqueda.fallo(e.toString());
    }
  }

  Future<void> stopScan() async {
    try { await FlutterBluePlus.stopScan(); } catch (_) { /* ya estaba parada */ }
  }

  // ── LA BANDA DE SIEMPRE ───────────────────────────────────────────────
  //
  // Se recuerda cuál se usó la última vez para poder ponerla la primera y
  // marcarla. La otra mitad de "la encuentra pero no es la correcta" es que
  // había que elegir a ciegas entre nombres parecidos —la banda y el reloj
  // Garmin anuncian los dos— y en modo ampliado salen hasta los altavoces.
  static const _kUltimaId     = 'ble_ultima_banda_id';
  static const _kUltimaNombre = 'ble_ultima_banda_nombre';

  Future<({String id, String nombre})?> ultimaBanda() async {
    final p = await SharedPreferences.getInstance();
    final id = p.getString(_kUltimaId);
    if (id == null || id.isEmpty) return null;
    return (id: id, nombre: p.getString(_kUltimaNombre) ?? '');
  }

  Future<void> _recordarBanda(BluetoothDevice d) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kUltimaId, d.remoteId.str);
    await p.setString(_kUltimaNombre, d.platformName);
  }

  /// Devuelve `true` si el dispositivo envía frecuencia cardíaca de verdad.
  ///
  /// ⚠️ ANTES ESTO NO SE DEVOLVÍA Y ERA UN FALLO MUDO. Si te conectabas a algo
  /// que no es una banda —fácil en modo ampliado, donde salían el reloj, los
  /// auriculares y hasta la tele, todos con un corazón rojo al lado— la
  /// conexión funcionaba, la pantalla decía "conectado" y luego se quedaba en
  /// "Esperando dato…" para siempre. Nadie te decía que te habías equivocado de
  /// aparato.
  Future<bool> connect(BluetoothDevice device) async {
    if (_device != null) await disconnect();
    _device = device;
    _desconexionPedida = false;

    await device.connect(autoConnect: false, timeout: const Duration(seconds: 15));
    _stateController.add(true);

    _stateSub = device.connectionState.listen((state) {
      final connected = state == BluetoothConnectionState.connected;
      _stateController.add(connected);
      if (!connected) {
        _hrSub?.cancel();
        // ⚠️ ANTES SE QUEDABA AQUÍ. Se cancelaba la suscripción y no había ni
        // un intento de volver. Sesión del 06/08: la banda estaba puesta y
        // funcionando —el Fenix 7 registró pulso los 45 minutos— pero el enlace
        // con el móvil se cayó en el minuto 5:30 y la app se quedó SIN FC el
        // resto del entreno. 40 minutos perdidos por un corte de unos segundos.
        _intentarReconectar();
      }
    });

    final tieneFc = await _subscribeHR(device);
    // Solo se recuerda la que de verdad da pulsaciones: recordar un altavoz
    // sería ofrecerte mañana el mismo error como si fuera tu banda.
    if (tieneFc) await _recordarBanda(device);
    return tieneFc;
  }

  // ── RECONEXIÓN ────────────────────────────────────────────────────────
  // Un corte de Bluetooth es lo más normal del mundo: el móvil en el bolsillo,
  // el brazo tapando la antena, el reloj peleando por la banda. Lo que no es
  // normal es no volver a intentarlo.
  //
  // Reintento con espera creciente (2, 4, 8… hasta 30 s) y SIN límite de
  // intentos mientras dure la sesión: si vuelve a estar a tiro en el minuto 40,
  // se recuperan los últimos cinco.
  bool _desconexionPedida = false;
  bool _reconectando      = false;

  Future<void> _intentarReconectar() async {
    if (_desconexionPedida || _reconectando || _device == null) return;
    _reconectando = true;
    var espera = 2;

    while (!_desconexionPedida && _device != null) {
      await Future.delayed(Duration(seconds: espera));
      if (_desconexionPedida || _device == null) break;
      if (_device!.isConnected) break;   // volvió solo

      try {
        await _device!.connect(autoConnect: false, timeout: const Duration(seconds: 10));
        await _subscribeHR(_device!);
        _stateController.add(true);
        break;
      } catch (_) {
        // Sigue fuera de alcance o apagada: se espera un poco más.
        espera = espera >= 30 ? 30 : espera * 2;
      }
    }
    _reconectando = false;
  }

  Future<bool> _subscribeHR(BluetoothDevice device) async {
    // Al reconectar esto se llama otra vez: sin cancelar la anterior quedarían
    // dos suscripciones vivas y cada latido entraría por duplicado en la media.
    await _hrSub?.cancel();
    _hrSub = null;

    // Breve pausa: el HRM-Pro Plus necesita ~300 ms tras la conexión BLE
    // para tener el GATT listo antes de discover services.
    await Future.delayed(const Duration(milliseconds: 300));

    final services = await device.discoverServices();
    for (final svc in services) {
      // Búsqueda flexible: acepta UUID corto ("180d") o largo completo
      if (!svc.uuid.str.toLowerCase().contains('180d')) continue;

      for (final char in svc.characteristics) {
        if (!char.uuid.str.toLowerCase().contains('2a37')) continue;

        // lastValueStream emite todas las notificaciones BLE recibidas del dispositivo.
        // Se omite el primer valor (caché vacía) con skip(1).
        _hrSub = char.lastValueStream.skip(1).listen((data) {
          if (data.isEmpty) return;
          _hrController.add(_parseHR(data));
          final rr = _parseRR(data);
          if (rr.isNotEmpty) _rrController.add(rr);
        });

        await char.setNotifyValue(true);
        return true;
      }
    }
    // Aquí NO hay frecuencia cardíaca en el aparato al que nos hemos conectado.
    // Antes esto se quedaba callado y la pantalla decía "Esperando dato…" hasta
    // el fin de los tiempos. Ahora se devuelve la verdad y quien llama lo dice.
    return false;
  }

  Future<void> disconnect() async {
    // Marca que la desconexión es NUESTRA: sin esto, el bucle de reconexión se
    // pondría a perseguir una banda que el propio atleta acaba de soltar.
    _desconexionPedida = true;
    _hrSub?.cancel();
    _stateSub?.cancel();
    await _device?.disconnect();
    _device = null;
    _stateController.add(false);
  }

  // Standard BLE HR Measurement (0x2A37) parsing.
  // Bit 0 del byte flags: 0 = HR en uint8, 1 = HR en uint16 little-endian.
  int _parseHR(List<int> value) {
    final flags = value[0];
    return (flags & 0x01) == 0 ? value[1] : (value[2] << 8 | value[1]);
  }

  // Intervalos R-R (ms) del HR Measurement (0x2A37), si el flag bit 4 los marca
  // presentes. Cada R-R es uint16 little-endian en unidades de 1/1024 s. Esto es
  // lo que permite un HRV (rMSSD) PRECISO con banda de pecho — la cámara solo
  // estima. El offset salta flags + HR (1 o 2 bytes) + energía gastada (bit 3).
  List<double> _parseRR(List<int> v) {
    if (v.isEmpty) return const [];
    final flags = v[0];
    if ((flags & 0x10) == 0) return const []; // bit 4: sin R-R
    int i = 1 + ((flags & 0x01) == 0 ? 1 : 2); // tras flags + HR
    if ((flags & 0x08) != 0) i += 2; // energía gastada presente (bit 3)
    final out = <double>[];
    while (i + 1 < v.length) {
      final raw = v[i] | (v[i + 1] << 8);
      out.add(raw * 1000.0 / 1024.0); // → ms
      i += 2;
    }
    return out;
  }

  void dispose() {
    _hrSub?.cancel();
    _stateSub?.cancel();
    _hrController.close();
    _rrController.close();
    _stateController.close();
  }
}

final bleServiceProvider = Provider<BleService>((_) => BleService());
