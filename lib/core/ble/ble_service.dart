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
  final _stateController = StreamController<bool>.broadcast();

  Stream<int>  get hrStream        => _hrController.stream;
  Stream<bool> get connectedStream => _stateController.stream;

  bool    get isConnected         => _device?.isConnected ?? false;
  String? get connectedDeviceName => _device?.platformName;

  // Scan filtrado por Heart Rate Service UUID (0x180D) durante 10 s.
  // Devuelve el stream de resultados para que la UI los muestre en vivo.
  Stream<List<ScanResult>> scan() {
    FlutterBluePlus.startScan(
      withServices: [Guid(_hrServiceUuid)],
      timeout: const Duration(seconds: 10),
    );
    return FlutterBluePlus.scanResults;
  }

  Future<void> stopScan() => FlutterBluePlus.stopScan();

  Future<void> connect(BluetoothDevice device) async {
    if (_device != null) await disconnect();
    _device = device;

    await device.connect(autoConnect: false, timeout: const Duration(seconds: 15));
    _stateController.add(true);

    _stateSub = device.connectionState.listen((state) {
      final connected = state == BluetoothConnectionState.connected;
      _stateController.add(connected);
      if (!connected) _hrSub?.cancel();
    });

    await _subscribeHR(device);
  }

  Future<void> _subscribeHR(BluetoothDevice device) async {
    final services = await device.discoverServices();
    for (final svc in services) {
      if (svc.uuid.str.toLowerCase() == _hrServiceUuid) {
        for (final char in svc.characteristics) {
          if (char.uuid.str.toLowerCase() == _hrMeasurementUuid) {
            await char.setNotifyValue(true);
            _hrSub = char.lastValueStream.listen((data) {
              if (data.isNotEmpty) _hrController.add(_parseHR(data));
            });
            return;
          }
        }
      }
    }
  }

  Future<void> disconnect() async {
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

  void dispose() {
    _hrSub?.cancel();
    _stateSub?.cancel();
    _hrController.close();
    _stateController.close();
  }
}

final bleServiceProvider = Provider<BleService>((_) => BleService());
