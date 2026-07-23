import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_client.dart';
import 'history_provider.dart'; // reutiliza HistoryState (month + sessions + byDay)

// ── Calendario del PLAN (mensual) ────────────────────────────────
// Mismo estado que el historial (getHistory devuelve TODO el mes, pasado y
// futuro), pero a diferencia del historial SÍ permite navegar a meses
// FUTUROS: el plan mira hacia adelante. NO es autoDispose: si se destruye
// entre la carga diferida y el primer build, la carga cae en una instancia
// muerta y el calendario sale vacío (bug real visto en v7.4.5).
class PlanCalendarNotifier extends StateNotifier<HistoryState> {
  final ApiClient _api;

  PlanCalendarNotifier(this._api)
      : super(HistoryState(
            month: DateTime(DateTime.now().year, DateTime.now().month)));

  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final data = await _api.getHistory(
        year: state.month.year,
        month: state.month.month,
      );
      final sessions = (data['sessions'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      state = state.copyWith(isLoading: false, sessions: sessions);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> goToPrevMonth() async {
    final m = state.month;
    state = state.copyWith(month: DateTime(m.year, m.month - 1));
    await load();
  }

  Future<void> goToNextMonth() async {
    final m = state.month;
    final now = DateTime.now();
    final next = DateTime(m.year, m.month + 1);
    // Cap suave a +12 meses: evita paginar al infinito por meses vacíos.
    final maxMonth = DateTime(now.year, now.month + 12);
    if (next.isAfter(maxMonth)) return;
    state = state.copyWith(month: next);
    await load();
  }
}

final planCalendarProvider =
    StateNotifierProvider<PlanCalendarNotifier, HistoryState>((ref) {
  return PlanCalendarNotifier(ref.read(apiClientProvider));
});
