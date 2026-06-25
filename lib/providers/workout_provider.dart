import 'dart:async';
import 'dart:math';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_client.dart';
import '../core/ble/ble_service.dart';
import '../core/gps/gps_service.dart';

// ── Dashboard State ──────────────────────────────────────────────
class DashboardState {
  final Map<String, dynamic>? todaySession;
  final Map<String, dynamic>? fitness;
  final int pendingAlerts;
  final Map<String, dynamic>? latestWellness;
  final bool isLoading;
  final String? error;

  const DashboardState({
    this.todaySession,
    this.fitness,
    this.pendingAlerts = 0,
    this.latestWellness,
    this.isLoading = false,
    this.error,
  });

  DashboardState copyWith({
    Map<String, dynamic>? todaySession,
    Map<String, dynamic>? fitness,
    int? pendingAlerts,
    Map<String, dynamic>? latestWellness,
    bool? isLoading,
    String? error,
  }) =>
      DashboardState(
        todaySession:   todaySession   ?? this.todaySession,
        fitness:        fitness        ?? this.fitness,
        pendingAlerts:  pendingAlerts  ?? this.pendingAlerts,
        latestWellness: latestWellness ?? this.latestWellness,
        isLoading:      isLoading      ?? this.isLoading,
        error:          error,
      );
}

class DashboardNotifier extends StateNotifier<DashboardState> {
  final ApiClient _api;

  DashboardNotifier(this._api) : super(const DashboardState());

  Future<void> load() async {
    state = state.copyWith(isLoading: true);
    try {
      final data = await _api.getDashboard();
      state = DashboardState(
        todaySession:   data['today_session'] as Map<String, dynamic>?,
        fitness:        data['fitness']       as Map<String, dynamic>?,
        pendingAlerts:  (data['pending_alerts'] as int?) ?? 0,
        latestWellness: data['latest_wellness'] as Map<String, dynamic>?,
        isLoading:      false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }
}

// ── Active Session State ─────────────────────────────────────────
class ActiveSessionState {
  final Map<String, dynamic>? session;
  final bool    isRunning;
  final DateTime? startedAt;
  final int     elapsedSeconds;
  final int?    currentHR;
  final double? currentPace;
  // Fase 2 — BLE
  final String? bleDeviceName;
  final bool    bleConnected;
  final int?    hrMin;
  final int?    hrMax;
  final int     hrSum;
  final int     hrCount;
  // Fase 2 — GPS
  final double  totalDistanceM;
  final bool    gpsActive;

  const ActiveSessionState({
    this.session,
    this.isRunning      = false,
    this.startedAt,
    this.elapsedSeconds = 0,
    this.currentHR,
    this.currentPace,
    this.bleDeviceName,
    this.bleConnected   = false,
    this.hrMin,
    this.hrMax,
    this.hrSum          = 0,
    this.hrCount        = 0,
    this.totalDistanceM = 0,
    this.gpsActive      = false,
  });

  int? get hrAvg => hrCount > 0 ? (hrSum / hrCount).round() : null;

  ActiveSessionState copyWith({
    Map<String, dynamic>? session,
    bool?    isRunning,
    DateTime? startedAt,
    int?     elapsedSeconds,
    int?     currentHR,
    double?  currentPace,
    String?  bleDeviceName,
    bool?    bleConnected,
    int?     hrMin,
    int?     hrMax,
    int?     hrSum,
    int?     hrCount,
    double?  totalDistanceM,
    bool?    gpsActive,
  }) =>
      ActiveSessionState(
        session:        session        ?? this.session,
        isRunning:      isRunning      ?? this.isRunning,
        startedAt:      startedAt      ?? this.startedAt,
        elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
        currentHR:      currentHR      ?? this.currentHR,
        currentPace:    currentPace    ?? this.currentPace,
        bleDeviceName:  bleDeviceName  ?? this.bleDeviceName,
        bleConnected:   bleConnected   ?? this.bleConnected,
        hrMin:          hrMin          ?? this.hrMin,
        hrMax:          hrMax          ?? this.hrMax,
        hrSum:          hrSum          ?? this.hrSum,
        hrCount:        hrCount        ?? this.hrCount,
        totalDistanceM: totalDistanceM ?? this.totalDistanceM,
        gpsActive:      gpsActive      ?? this.gpsActive,
      );
}

class ActiveSessionNotifier extends StateNotifier<ActiveSessionState> {
  final ApiClient  _api;
  final BleService _ble;
  final GpsService _gps;

  StreamSubscription<int>?      _hrSub;
  StreamSubscription<GpsPoint>? _gpsSub;

  ActiveSessionNotifier(this._api, this._ble, this._gps)
      : super(const ActiveSessionState());

  // ── API ─────────────────────────────────────────────────────

  // Marca la sesión como corriendo localmente (antes del API call).
  void markAsRunning() {
    if (state.isRunning) return;
    state = state.copyWith(isRunning: true, startedAt: DateTime.now());
  }

  // Pre-carga datos de la sesión (bloques del plan) antes de iniciar.
  Future<void> loadSession(String sessionId) async {
    try {
      final data = await _api.getSession(sessionId);
      state = state.copyWith(session: data);
    } catch (_) {
      // Silencioso: los bloques se cargan igualmente al hacer startSession
    }
  }

  Future<void> startSession(String sessionId) async {
    final result = await _api.startSession(sessionId);
    state = state.copyWith(
      isRunning:  true,
      startedAt:  state.startedAt ?? DateTime.now(),
      session:    result,
    );
  }

  void updateHR(int bpm) => state = state.copyWith(currentHR: bpm);
  void updatePace(double secPerKm) => state = state.copyWith(currentPace: secPerKm);
  void tickSecond() =>
      state = state.copyWith(elapsedSeconds: state.elapsedSeconds + 1);

  Future<Map<String, dynamic>> completeSession(
    String sessionId,
    Map<String, dynamic> actuals,
  ) async {
    final result = await _api.completeSession(sessionId, actuals);
    state = const ActiveSessionState();
    return result;
  }

  // ── BLE ─────────────────────────────────────────────────────
  Future<void> connectBLE(BluetoothDevice device) async {
    // BleScanScreen ya puede haber conectado el device; solo conectar si no lo está.
    if (!_ble.isConnected) {
      await _ble.connect(device);
    }
    state = state.copyWith(
      bleDeviceName: device.platformName.isNotEmpty
          ? device.platformName
          : device.remoteId.str,
      bleConnected: true,
    );
    _hrSub?.cancel();
    _hrSub = _ble.hrStream.listen(_onHR);
  }

  void _onHR(int bpm) {
    state = state.copyWith(
      currentHR: bpm,
      hrMin: state.hrMin == null ? bpm : min(state.hrMin!, bpm),
      hrMax: state.hrMax == null ? bpm : max(state.hrMax!, bpm),
      hrSum: state.hrSum + bpm,
      hrCount: state.hrCount + 1,
    );
  }

  Future<void> disconnectBLE() async {
    _hrSub?.cancel();
    await _ble.disconnect();
    state = state.copyWith(bleConnected: false);
  }

  // ── GPS ─────────────────────────────────────────────────────
  void startGPS() {
    _gps.startTracking();
    _gpsSub = _gps.locationStream.listen(_onGpsPoint);
    state = state.copyWith(gpsActive: true);
  }

  void _onGpsPoint(GpsPoint point) {
    final pace = point.speedMps > 0.5 ? 1000 / point.speedMps : (state.currentPace ?? 0);
    state = state.copyWith(
      currentPace:    pace,
      totalDistanceM: _gps.totalDistanceM,
    );
  }

  // Detiene GPS y devuelve el track completo para subir al backend
  GpsTrack stopGPS() {
    _gpsSub?.cancel();
    state = state.copyWith(gpsActive: false);
    return _gps.stopTracking();
  }

  // Construye el payload de actuals incluyendo datos de sensores.
  // Los valores manuales del formulario tienen preferencia si se pasan.
  Map<String, dynamic> buildActuals({
    int?    manualDurationMin,
    double? manualDistanceM,
    int?    manualRpe,
    int?    manualHrAvg,
    int?    manualHrMax,
    Map<String, dynamic>? athleteFeedback,
  }) =>
      {
        'actualDurationMin': manualDurationMin ?? (state.elapsedSeconds ~/ 60),
        'actualDistanceM':   (manualDistanceM ?? state.totalDistanceM).round(),
        'actualHrAvgBpm':    manualHrAvg ?? state.hrAvg,
        'actualHrMaxBpm':    manualHrMax ?? state.hrMax,
        'actualRpe':         manualRpe,
        if (athleteFeedback != null) 'athleteFeedback': athleteFeedback,
      };

  @override
  void dispose() {
    _hrSub?.cancel();
    _gpsSub?.cancel();
    super.dispose();
  }
}

// ── Providers ────────────────────────────────────────────────────
final dashboardProvider =
    StateNotifierProvider<DashboardNotifier, DashboardState>(
  (ref) => DashboardNotifier(ref.read(apiClientProvider)),
);

final activeSessionProvider =
    StateNotifierProvider<ActiveSessionNotifier, ActiveSessionState>(
  (ref) => ActiveSessionNotifier(
    ref.read(apiClientProvider),
    ref.read(bleServiceProvider),
    ref.read(gpsServiceProvider),
  ),
);
