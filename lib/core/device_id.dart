import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

const _kDeviceIdKey = 'ro_device_id';
const _storage = FlutterSecureStorage();

/// Devuelve el device_id único y persistente de este dispositivo.
/// Se genera la primera vez y se guarda en almacenamiento seguro.
Future<String> getOrCreateDeviceId() async {
  final existing = await _storage.read(key: _kDeviceIdKey);
  if (existing != null && existing.isNotEmpty) return existing;

  final newId = const Uuid().v4();
  await _storage.write(key: _kDeviceIdKey, value: newId);
  return newId;
}
