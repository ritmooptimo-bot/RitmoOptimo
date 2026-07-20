import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_client.dart';

class HistoryState {
  final List<Map<String, dynamic>> sessions;
  final bool isLoading;
  final String? error;
  final DateTime month;

  const HistoryState({
    this.sessions = const [],
    this.isLoading = false,
    this.error,
    required this.month,
  });

  HistoryState copyWith({
    List<Map<String, dynamic>>? sessions,
    bool? isLoading,
    String? error,
    DateTime? month,
  }) =>
      HistoryState(
        sessions: sessions ?? this.sessions,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        month: month ?? this.month,
      );

  // Sessions indexed by day-of-month for O(1) calendar lookup
  Map<int, List<Map<String, dynamic>>> get byDay {
    final map = <int, List<Map<String, dynamic>>>{};
    for (final s in sessions) {
      final raw = s['scheduled_date'] as String?;
      if (raw == null) continue;
      // Recorta a 'YYYY-MM-DD' antes de parsear el día
      final datePart = raw.length >= 10 ? raw.substring(0, 10) : raw;
      final day = int.tryParse(datePart.split('-').last) ?? 0;
      (map[day] ??= []).add(s);
    }
    return map;
  }
}

class HistoryNotifier extends StateNotifier<HistoryState> {
  final ApiClient _api;

  HistoryNotifier(this._api)
      : super(HistoryState(month: DateTime(DateTime.now().year, DateTime.now().month)));

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
    // Do not allow navigating beyond current month
    if (next.year > now.year || (next.year == now.year && next.month > now.month)) return;
    state = state.copyWith(month: next);
    await load();
  }
}

final historyProvider =
    StateNotifierProvider<HistoryNotifier, HistoryState>((ref) {
  return HistoryNotifier(ref.read(apiClientProvider));
});
