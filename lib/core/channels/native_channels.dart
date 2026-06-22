import 'package:flutter/services.dart';

// ── BLE — Sensor de Frecuencia Cardíaca ─────────────────────────
// Flutter pierde BLE tras ~15min con pantalla bloqueada en iOS.
// Swift CBCentralManager con 'bluetooth-central' background mode
// mantiene la conexión; Flutter solo recibe el stream de datos.
class BLEChannel {
  static const _method = MethodChannel('flutter.ritmooptimo.com/ble');
  static const _event  = EventChannel('flutter.ritmooptimo.com/ble/stream');

  static Future<List<Map<String, dynamic>>> scanDevices() async {
    final result = await _method.invokeMethod<List>('scanDevices');
    return (result ?? []).cast<Map<String, dynamic>>();
  }

  static Future<void> startMonitoring(String deviceId) =>
      _method.invokeMethod('startMonitoring', {'deviceId': deviceId});

  static Future<void> stopMonitoring() =>
      _method.invokeMethod('stopMonitoring');

  // Stream de datos: {hr: int, battery: int, timestamp: String}
  static Stream<Map<String, dynamic>> get hrStream =>
      _event.receiveBroadcastStream().cast<Map<Object?, Object?>>().map(
        (e) => e.map((k, v) => MapEntry(k.toString(), v)),
      );
}

// ── GPS — Tracks de Sesión al Aire Libre ────────────────────────
class GPSChannel {
  static const _method = MethodChannel('flutter.ritmooptimo.com/gps');
  static const _event  = EventChannel('flutter.ritmooptimo.com/gps/stream');

  static Future<void> startTracking() =>
      _method.invokeMethod('startTracking');

  static Future<void> stopTracking() =>
      _method.invokeMethod('stopTracking');

  // Stream de datos: {lat, lng, alt, speed_mps, accuracy, timestamp}
  static Stream<Map<String, dynamic>> get locationStream =>
      _event.receiveBroadcastStream().cast<Map<Object?, Object?>>().map(
        (e) => e.map((k, v) => MapEntry(k.toString(), v)),
      );
}
