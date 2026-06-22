import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _kTokenKey = 'auth_token';
const _apiBase   = 'https://ritmooptimo.tech/api/training-plan';

// ── Auth Interceptor ─────────────────────────────────────────────
class _AuthInterceptor extends Interceptor {
  final FlutterSecureStorage _storage;

  _AuthInterceptor(this._storage);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _storage.read(key: _kTokenKey);
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // Token expirado — la app debe navegar a login
    if (err.response?.statusCode == 401) {
      _storage.delete(key: _kTokenKey);
    }
    handler.next(err);
  }
}

// ── Retry Interceptor (offline queue) ───────────────────────────
class _RetryInterceptor extends Interceptor {
  final Dio dio;
  _RetryInterceptor(this.dio);

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    // Reintentar una vez en errores de red (no en errores HTTP 4xx/5xx)
    if (err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.receiveTimeout) {
      try {
        final response = await dio.fetch(err.requestOptions);
        return handler.resolve(response);
      } catch (_) {
        // Si el reintento falla, propagar el error original
      }
    }
    handler.next(err);
  }
}

// ── ApiClient ────────────────────────────────────────────────────
class ApiClient {
  late final Dio _dio;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  ApiClient() {
    _dio = Dio(BaseOptions(
      baseUrl: _apiBase,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));
    _dio.interceptors.addAll([
      _AuthInterceptor(_storage),
      _RetryInterceptor(_dio),
    ]);
  }

  // ── Token management ─────────────────────────────────────────
  Future<void> saveToken(String token) =>
      _storage.write(key: _kTokenKey, value: token);

  Future<void> clearToken() => _storage.delete(key: _kTokenKey);

  Future<bool> hasToken() async =>
      (await _storage.read(key: _kTokenKey)) != null;

  // ── Athlete Dashboard (P0) ───────────────────────────────────
  Future<Map<String, dynamic>> getDashboard() async {
    final r = await _dio.get('/athlete/dashboard');
    return r.data as Map<String, dynamic>;
  }

  // ── Week Plan (P0) ───────────────────────────────────────────
  Future<Map<String, dynamic>> getWeekPlan() async {
    final r = await _dio.get('/athlete/week');
    return r.data as Map<String, dynamic>;
  }

  // ── Today Session (P0) ──────────────────────────────────────
  Future<Map<String, dynamic>> getTodaySession() async {
    final r = await _dio.get('/athlete/today');
    return r.data as Map<String, dynamic>;
  }

  // ── Session Start (P1) ───────────────────────────────────────
  Future<Map<String, dynamic>> startSession(String sessionId) async {
    final r = await _dio.post('/sessions/$sessionId/start');
    return r.data as Map<String, dynamic>;
  }

  // ── Session Complete (P1) ────────────────────────────────────
  Future<Map<String, dynamic>> completeSession(
    String sessionId,
    Map<String, dynamic> actuals,
  ) async {
    final r = await _dio.post('/sessions/$sessionId/complete', data: actuals);
    return r.data as Map<String, dynamic>;
  }

  // ── Wellness (P1) ────────────────────────────────────────────
  Future<Map<String, dynamic>> postWellness(Map<String, dynamic> data) async {
    final r = await _dio.post('/wellness', data: data);
    return r.data as Map<String, dynamic>;
  }

  // ── HRV (P1) ─────────────────────────────────────────────────
  Future<Map<String, dynamic>> postHRV(Map<String, dynamic> data) async {
    final r = await _dio.post('/hrv', data: data);
    return r.data as Map<String, dynamic>;
  }

  Future<List<dynamic>> getHRVHistory({int days = 30}) async {
    final r = await _dio.get('/hrv', queryParameters: {'days': days});
    return r.data as List<dynamic>;
  }

  // ── HR Recovery (P1) ─────────────────────────────────────────
  Future<Map<String, dynamic>> postHRRecovery(Map<String, dynamic> data) async {
    final r = await _dio.post('/hr-recovery', data: data);
    return r.data as Map<String, dynamic>;
  }

  // ── Thresholds (P1) ─────────────────────────────────────────
  Future<List<dynamic>> getThresholds({String? sport}) async {
    final r = await _dio.get('/athlete/thresholds',
        queryParameters: sport != null ? {'sport': sport} : null);
    return r.data as List<dynamic>;
  }

  // ── GPS Track (P2) ───────────────────────────────────────────
  Future<Map<String, dynamic>> postGPSTrack(
    String sessionId,
    Map<String, dynamic> trackData,
  ) async {
    final r = await _dio.post('/sessions/$sessionId/gps-track', data: trackData);
    return r.data as Map<String, dynamic>;
  }

  // ── Actual Structure (existente) ─────────────────────────────
  Future<Map<String, dynamic>> postActualStructure(
    String sessionId,
    List<Map<String, dynamic>> blocks,
  ) async {
    final r = await _dio.post('/sessions/$sessionId/actual-structure',
        data: {'blocks': blocks, 'source': 'athlete'});
    return r.data as Map<String, dynamic>;
  }

  // ── Auth (usa base URL diferente) ────────────────────────────
  Future<String> loginAthlete(String email, String password) async {
    final authDio = Dio(BaseOptions(
      baseUrl: 'https://ritmooptimo.tech/api/auth',
      connectTimeout: const Duration(seconds: 10),
    ));
    final r = await authDio.post('/login', data: {
      'email': email,
      'password': password,
    });
    final token = r.data['token'] as String;
    await saveToken(token);
    return token;
  }
}

// ── Riverpod Provider ─────────────────────────────────────────────
final apiClientProvider = Provider<ApiClient>((_) => ApiClient());
