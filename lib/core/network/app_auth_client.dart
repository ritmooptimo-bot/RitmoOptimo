import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../device_id.dart';

const _kAccessTokenKey  = 'ro_access_token';
const _kRefreshTokenKey = 'ro_refresh_token';

const _baseUrl = 'https://ritmooptimo.tech/api/app';

// ── AppAuthClient ─────────────────────────────────────────────────
// Gestiona autenticación exclusiva de la app móvil:
// pairing con QR token, login con device_id, renovación de sesión.
class AppAuthClient {
  late final Dio _dio;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  AppAuthClient() {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));
  }

  // ── Device Pairing ────────────────────────────────────────────
  /// Vincula este dispositivo usando el token del QR (uso único, 48h).
  /// Guarda access_token y refresh_token en almacenamiento seguro.
  Future<Map<String, dynamic>> pairDevice({
    required String pairingToken,
    required String platform, // 'android' | 'ios'
    String? deviceName,
  }) async {
    final deviceId = await getOrCreateDeviceId();

    final r = await _dio.post('/pair-device', data: {
      'token':       pairingToken,
      'device_id':   deviceId,
      'platform':    platform,
      'device_name': deviceName,
    });

    final data = r.data as Map<String, dynamic>;
    await _saveTokens(data['access_token'] as String, data['refresh_token'] as String);
    return data;
  }

  // ── Login con validación de dispositivo ──────────────────────
  Future<Map<String, dynamic>> loginWithDevice({
    required String email,
    required String password,
  }) async {
    final deviceId = await getOrCreateDeviceId();

    final r = await _dio.post('/login', data: {
      'email':     email,
      'password':  password,
      'device_id': deviceId,
    });

    final data = r.data as Map<String, dynamic>;
    await _saveTokens(data['access_token'] as String, data['refresh_token'] as String);
    return data;
  }

  // ── Renovar sesión (refresh token) ───────────────────────────
  Future<bool> refreshSession() async {
    final refreshToken = await _storage.read(key: _kRefreshTokenKey);
    final deviceId     = await getOrCreateDeviceId();
    if (refreshToken == null) return false;

    try {
      final r = await _dio.post('/refresh-token', data: {
        'refresh_token': refreshToken,
        'device_id':     deviceId,
      });
      final data = r.data as Map<String, dynamic>;
      await _saveTokens(data['access_token'] as String, data['refresh_token'] as String);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Token utils ───────────────────────────────────────────────
  Future<String?> getAccessToken() => _storage.read(key: _kAccessTokenKey);

  Future<bool> hasValidSession() async =>
      (await _storage.read(key: _kAccessTokenKey)) != null;

  Future<void> clearSession() async {
    await _storage.delete(key: _kAccessTokenKey);
    await _storage.delete(key: _kRefreshTokenKey);
  }

  Future<void> _saveTokens(String access, String refresh) async {
    await _storage.write(key: _kAccessTokenKey,  value: access);
    await _storage.write(key: _kRefreshTokenKey, value: refresh);
  }
}

final appAuthClientProvider = Provider<AppAuthClient>((_) => AppAuthClient());
