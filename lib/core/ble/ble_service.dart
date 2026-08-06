import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _hrServiceUuid     = "0000180d-0000-1000-8000-00805f9b34fb";
const _hrMeasurementUuid = "00002a37-0000-1000-8000-00805f9b34fb";

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

  // Scan filtrado por Heart Rate Service UUID (0x180D) durante 20 s.
  // 20s necesarios para bandas Garmin (HRM-Pro Plus tarda en anunciar BLE
  // cuando también transmite ANT+ a un reloj emparejado).
  Stream<List<ScanResult>> scan() {
    FlutterBluePlus.startScan(
      withServices: [Guid(_hrServiceUuid)],
      timeout: const Duration(seconds: 20),
    );
    return FlutterBluePlus.scanResults;
  }

  Future<void> stopScan() => FlutterBluePlus.stopScan();

  Future<void> connect(BluetoothDevice device) async {
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

    await _subscribeHR(device);
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

  Future<void> _subscribeHR(BluetoothDevice device) async {
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
        return;
      }
    }
    // Si llega aquí: el servicio HR no se encontró en el dispositivo conectado.
    // No lanzamos excepción — la UI mostrará "Esperando dato..."
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
