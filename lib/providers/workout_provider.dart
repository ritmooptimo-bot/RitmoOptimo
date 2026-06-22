import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_client.dart';

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
  final bool isRunning;
  final DateTime? startedAt;
  final int elapsedSeconds;
  final int? currentHR;
  final double? currentPace;

  const ActiveSessionState({
    this.session,
    this.isRunning = false,
    this.startedAt,
    this.elapsedSeconds = 0,
    this.currentHR,
    this.currentPace,
  });

  ActiveSessionState copyWith({
    Map<String, dynamic>? session,
    bool? isRunning,
    DateTime? startedAt,
    int? elapsedSeconds,
    int? currentHR,
    double? currentPace,
  }) =>
      ActiveSessionState(
        session:        session        ?? this.session,
        isRunning:      isRunning      ?? this.isRunning,
        startedAt:      startedAt      ?? this.startedAt,
        elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
        currentHR:      currentHR      ?? this.currentHR,
        currentPace:    currentPace    ?? this.currentPace,
      );
}

class ActiveSessionNotifier extends StateNotifier<ActiveSessionState> {
  final ApiClient _api;

  ActiveSessionNotifier(this._api) : super(const ActiveSessionState());

  Future<void> startSession(String sessionId) async {
    final result = await _api.startSession(sessionId);
    state = state.copyWith(
      isRunning:  true,
      startedAt:  DateTime.now(),
      session:    result,
    );
  }

  void updateHR(int bpm) => state = state.copyWith(currentHR: bpm);
  void updatePace(double secPerKm) => state = state.copyWith(currentPace: secPerKm);
  void tickSecond() => state = state.copyWith(elapsedSeconds: state.elapsedSeconds + 1);

  Future<Map<String, dynamic>> completeSession(
    String sessionId,
    Map<String, dynamic> actuals,
  ) async {
    final result = await _api.completeSession(sessionId, actuals);
    state = const ActiveSessionState();
    return result;
  }
}

// ── Providers ────────────────────────────────────────────────────
final dashboardProvider =
    StateNotifierProvider<DashboardNotifier, DashboardState>(
  (ref) => DashboardNotifier(ref.read(apiClientProvider)),
);

final activeSessionProvider =
    StateNotifierProvider<ActiveSessionNotifier, ActiveSessionState>(
  (ref) => ActiveSessionNotifier(ref.read(apiClientProvider)),
);
