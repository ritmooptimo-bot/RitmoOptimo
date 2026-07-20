import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/history_provider.dart';
import '../../providers/skin_provider.dart';
import '../../models/sport.dart';
import '../../config/skins/skin_config.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  int? _selectedDay;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(historyProvider.notifier).load());
  }

  @override
  Widget build(BuildContext context) {
    final skin  = ref.watch(activeSkinProvider);
    final state = ref.watch(historyProvider);

    final visibleSessions = _selectedDay == null
        ? state.sessions
        : state.sessions.where((s) {
            final raw = s['scheduled_date'] as String? ?? '';
            final datePart = raw.length >= 10 ? raw.substring(0, 10) : raw;
            return int.tryParse(datePart.split('-').last) == _selectedDay;
          }).toList();

    return Scaffold(
      backgroundColor: skin.background,
      body: SafeArea(
        child: Column(
          children: [
            _Header(skin: skin, state: state, onPrev: () {
              setState(() => _selectedDay = null);
              ref.read(historyProvider.notifier).goToPrevMonth();
            }, onNext: () {
              setState(() => _selectedDay = null);
              ref.read(historyProvider.notifier).goToNextMonth();
            }),
            if (state.isLoading)
              Expanded(
                child: Center(
                  child: CircularProgressIndicator(color: skin.accent),
                ),
              )
            else ...[
              _CalendarGrid(
                skin: skin,
                state: state,
                selectedDay: _selectedDay,
                onDayTap: (day) => setState(() {
                  _selectedDay = _selectedDay == day ? null : day;
                }),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _SessionList(
                  skin: skin,
                  sessions: visibleSessions,
                  selectedDay: _selectedDay,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Header con navegación de mes ─────────────────────────────────

class _Header extends StatelessWidget {
  final SkinConfig skin;
  final HistoryState state;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _Header({
    required this.skin,
    required this.state,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final now   = DateTime.now();
    final m     = state.month;
    final isNow = m.year == now.year && m.month == now.month;

    final monthNames = [
      '', 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
      'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
    ];

    final completed = state.sessions.where((s) => s['status'] == 'completed').length;
    final missed    = state.sessions.where((s) => s['status'] == 'missed').length;
    final total     = state.sessions.length;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Historial', style: TextStyle(
                color: skin.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              )),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.chevron_left, color: skin.textPrimary),
                onPressed: onPrev,
              ),
              Text(
                '${monthNames[m.month]} ${m.year}',
                style: TextStyle(
                  color: skin.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              IconButton(
                icon: Icon(Icons.chevron_right,
                    color: isNow ? skin.textMuted : skin.textPrimary),
                onPressed: isNow ? null : onNext,
              ),
            ],
          ),
          if (total > 0)
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Row(
                children: [
                  _StatChip(color: const Color(0xFF4CAF50), label: '$completed realizadas'),
                  const SizedBox(width: 8),
                  _StatChip(color: const Color(0xFFEF5350), label: '$missed perdidas'),
                  const SizedBox(width: 8),
                  _StatChip(color: Colors.grey, label: '$total total'),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final Color color;
  final String label;
  const _StatChip({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// ── Calendario mensual compacto ───────────────────────────────────

class _CalendarGrid extends StatelessWidget {
  final SkinConfig skin;
  final HistoryState state;
  final int? selectedDay;
  final ValueChanged<int> onDayTap;

  const _CalendarGrid({
    required this.skin,
    required this.state,
    required this.selectedDay,
    required this.onDayTap,
  });

  @override
  Widget build(BuildContext context) {
    final m        = state.month;
    final byDay    = state.byDay;
    final firstDay = DateTime(m.year, m.month, 1);
    final daysInMonth = DateTime(m.year, m.month + 1, 0).day;
    // weekday: 1=Mon…7=Sun → offset to start grid on Monday
    final startOffset = (firstDay.weekday - 1) % 7;
    final today = DateTime.now();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: skin.backgroundCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // Day-of-week headers
          Row(
            children: ['L', 'M', 'X', 'J', 'V', 'S', 'D'].map((d) =>
              Expanded(
                child: Center(
                  child: Text(d, style: TextStyle(
                    color: skin.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  )),
                ),
              ),
            ).toList(),
          ),
          const SizedBox(height: 6),
          // Day cells
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
            ),
            itemCount: startOffset + daysInMonth,
            itemBuilder: (_, idx) {
              if (idx < startOffset) return const SizedBox.shrink();
              final day = idx - startOffset + 1;
              final sessions = byDay[day] ?? [];
              final isToday = m.year == today.year && m.month == today.month && day == today.day;
              final isSelected = selectedDay == day;

              Color? dotColor;
              if (sessions.isNotEmpty) {
                final hasCompleted = sessions.any((s) => s['status'] == 'completed');
                final hasMissed   = sessions.any((s) => s['status'] == 'missed');
                if (hasCompleted) {
                  dotColor = const Color(0xFF4CAF50);
                } else if (hasMissed) {
                  dotColor = const Color(0xFFEF5350);
                } else {
                  dotColor = const Color(0xFFFFA726);
                }
              }

              return GestureDetector(
                onTap: sessions.isEmpty ? null : () => onDayTap(day),
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected
                        ? skin.accent.withValues(alpha: 0.2)
                        : isToday
                            ? skin.accent.withValues(alpha: 0.08)
                            : null,
                    borderRadius: BorderRadius.circular(6),
                    border: isToday
                        ? Border.all(color: skin.accent.withValues(alpha: 0.5), width: 1)
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$day',
                        style: TextStyle(
                          color: isSelected
                              ? skin.accent
                              : sessions.isNotEmpty
                                  ? skin.textPrimary
                                  : skin.textMuted,
                          fontSize: 12,
                          fontWeight: sessions.isNotEmpty ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                      if (dotColor != null) ...[
                        const SizedBox(height: 2),
                        Container(
                          width: 5, height: 5,
                          decoration: BoxDecoration(
                            color: dotColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── Lista de sesiones ─────────────────────────────────────────────

class _SessionList extends ConsumerWidget {
  final SkinConfig skin;
  final List<Map<String, dynamic>> sessions;
  final int? selectedDay;

  const _SessionList({
    required this.skin,
    required this.sessions,
    required this.selectedDay,
  });

  // Emoji por DEPORTE (el de arriba es por tipo de sesión, que es otra cosa)
  static String _iconoDeporte(Sport s) => switch (s) {
        Sport.running  => '🏃',
        Sport.trail    => '⛰️',
        Sport.ciclismo => '🚴',
        Sport.natacion => '🏊',
        Sport.fuerza   => '🏋️',
        Sport.otro     => '🤸',
      };

  static const _icons = {
    'recuperacion': '🟩', 'base': '🟦', 'umbral': '🟧', 'vo2max': '🔴',
    'neuromuscular': '⬛', 'largo': '🟫', 'fuerza': '⚫', 'hiit': '🩷',
    'tecnica': '🔵', 'test': '🟡', 'competicion': '🏆', 'descanso': '⬜',
    'fartlek': '🌊', 'progresion': '📈', 'activacion': '⚡',
  };

  static const _statusColors = {
    'completed':         Color(0xFF4CAF50),
    'missed':            Color(0xFFEF5350),
    'scheduled':         Color(0xFF9E9E9E),
    'approved':          Color(0xFF42A5F5),
    'modified':          Color(0xFFFFA726),
    'pending_approval':  Color(0xFFAB47BC),
    'in_progress':       Color(0xFF29B6F6),
    'cancelled':         Color(0xFF78909C),
  };

  static const _statusLabels = {
    'completed':        'Realizada',
    'missed':           'Perdida',
    'scheduled':        'Programada',
    'approved':         'Aprobada',
    'modified':         'Modificada',
    'pending_approval': 'Pend. aprobación',
    'in_progress':      'En progreso',
    'cancelled':        'Cancelada',
  };

  String _formatDate(String? raw) {
    if (raw == null) return '';
    // Acepta tanto '2026-06-30' como '2026-06-30T00:00:00.000Z'
    final datePart = raw.length >= 10 ? raw.substring(0, 10) : raw;
    final parts = datePart.split('-');
    if (parts.length < 3) return raw;
    return '${parts[2]}/${parts[1]}';
  }

  String _formatDuration(dynamic planned, dynamic actual) {
    if (actual != null) {
      final min = num.tryParse(actual.toString())?.toInt() ?? 0;
      return '${min}min reales';
    }
    if (planned != null) {
      final min = num.tryParse(planned.toString())?.toInt() ?? 0;
      return '${min}min plan';
    }
    return '';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (sessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_month_outlined, color: skin.textMuted, size: 40),
            const SizedBox(height: 12),
            Text(
              selectedDay != null
                  ? 'Sin sesiones este día'
                  : 'Sin sesiones este mes',
              style: TextStyle(color: skin.textMuted, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      itemCount: sessions.length,
      itemBuilder: (_, i) {
        final s      = sessions[i];
        final status = s['status'] as String? ?? 'scheduled';
        final type   = s['session_type'] as String? ?? '';
        final esLibre = s['is_free_session'] == true;
        // El icono, por DEPORTE: una salida en bici llevaba el mismo cuadrado
        // azul que un rodaje porque se elegía por tipo de sesión.
        final deporte = Sport.fromApi(s['sport'] as String?);
        final icon   = esLibre || s['sport'] != null
            ? _iconoDeporte(deporte)
            : (_icons[type] ?? '●');
        final color  = _statusColors[status] ?? skin.textMuted;
        final label  = _statusLabels[status] ?? status;
        final dur    = _formatDuration(s['planned_duration_min'], s['actual_duration_min']);
        final date   = _formatDate(s['scheduled_date'] as String?);

        // Show date header when not filtered by day
        final showDate = selectedDay == null && (i == 0 ||
            (sessions[i - 1]['scheduled_date'] as String?) !=
                (s['scheduled_date'] as String?));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showDate)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 0, 6),
                child: Text(
                  date,
                  style: TextStyle(
                    color: skin.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            GestureDetector(
              onTap: () {
                final id     = s['id'] as String?;
                final status = s['status'] as String? ?? '';
                if (id == null) return;
                if (status == 'completed' || status == 'missed') {
                  context.push('/session/$id/summary');
                } else {
                  context.push('/session/$id');
                }
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: skin.backgroundCard,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: color.withValues(alpha: 0.25),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Text(icon, style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (esLibre) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF22C55E)
                                        .withValues(alpha: 0.16),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  // Que el deportista distinga de un vistazo lo
                                  // que eligió él de lo que le mandó el entrenador.
                                  child: const Text('LIBRE',
                                      style: TextStyle(
                                          color: Color(0xFF22C55E),
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.5)),
                                ),
                                const SizedBox(width: 6),
                              ],
                              Expanded(
                                child: Text(
                                  s['title'] as String? ?? type,
                                  style: TextStyle(
                                    color: skin.textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (dur.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(dur, style: TextStyle(color: skin.textMuted, fontSize: 12)),
                          ],
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right, color: skin.textMuted, size: 16),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
