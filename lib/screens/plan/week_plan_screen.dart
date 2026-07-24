import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/skin_provider.dart';
import '../../providers/plan_calendar_provider.dart';
import '../../config/skins/skin_config.dart';
import '../../core/network/api_client.dart';

// Vista LISTA (semanal) — FutureProvider autoDispose: se reinicia al abrir.
final _weekPlanProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final api = ref.read(apiClientProvider);
  return api.getWeekPlan();
});

// Nombre del entrenador asignado (para la cabecera "Plan · Entrenador: X").
final _coachNameProvider =
    FutureProvider.autoDispose<String?>((ref) async {
  final api = ref.read(apiClientProvider);
  return api.getCoach();
});

enum _PlanView { list, calendar }

class WeekPlanScreen extends ConsumerStatefulWidget {
  const WeekPlanScreen({super.key});

  @override
  ConsumerState<WeekPlanScreen> createState() => _WeekPlanScreenState();
}

class _WeekPlanScreenState extends ConsumerState<WeekPlanScreen> {
  _PlanView _view = _PlanView.calendar; // por defecto: Calendario
  bool _calendarLoaded = false; // carga perezosa: solo al abrir el calendario
  int? _selectedDay;

  @override
  void initState() {
    super.initState();
    // Vista por defecto = Calendario → se carga al abrir (post-frame para ref seguro).
    _calendarLoaded = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(planCalendarProvider.notifier).load();
    });
  }

  static String _todayStr() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  bool _isCurrentMonth(DateTime m) {
    final now = DateTime.now();
    return m.year == now.year && m.month == now.month;
  }

  bool _isTodayDate(Map<String, dynamic> s) {
    final raw = (s['scheduled_date'] ?? s['session_date']) as String? ?? '';
    return raw.length >= 10 && raw.substring(0, 10) == _todayStr();
  }

  void _switchTo(_PlanView v) {
    // El provider NO es autoDispose → su instancia persiste, así que cargar
    // aquí (en el handler del toque) es seguro y llega al build que la observa.
    if (v == _PlanView.calendar && !_calendarLoaded) {
      _calendarLoaded = true;
      ref.read(planCalendarProvider.notifier).load();
    }
    setState(() => _view = v);
  }

  void _openSession(Map<String, dynamic> s) {
    final id = s['id'] as String?;
    if (id == null) return;
    final status = s['status'] as String? ?? '';
    if (status == 'completed' || status == 'missed') {
      context.push('/session/$id/summary');
    } else {
      context.push('/session/$id');
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = ref.watch(activeSkinProvider);
    final coach = ref.watch(_coachNameProvider).valueOrNull;
    return Scaffold(
      backgroundColor: skin.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Plan'),
            if (coach != null && coach.trim().isNotEmpty)
              Text(
                'Entrenador: ${coach.trim()}',
                style: TextStyle(
                  fontSize: 12,
                  color: skin.textMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
        backgroundColor: skin.backgroundSecondary,
        foregroundColor: skin.textPrimary,
        elevation: 0,
      ),
      body: Column(
        children: [
          _ViewToggle(skin: skin, view: _view, onChanged: _switchTo),
          Expanded(
            child: _view == _PlanView.list
                ? _buildList(skin)
                : _buildCalendar(skin),
          ),
        ],
      ),
    );
  }

  // ── Vista LISTA (semanal) ──────────────────────────────────────
  Widget _buildList(SkinConfig skin) {
    final plan = ref.watch(_weekPlanProvider);
    return plan.when(
      loading: () => Center(child: CircularProgressIndicator(color: skin.accent)),
      error: (e, _) => _ErrorView(
        skin: skin,
        msg: e.toString().replaceAll('Exception:', '').trim(),
        onRetry: () => ref.invalidate(_weekPlanProvider),
      ),
      data: (data) {
        final sessions = (data['sessions'] as List?) ?? [];
        final weekFrom = data['week_from'] as String? ?? '';
        final weekTo = data['week_to'] as String? ?? '';
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(_weekPlanProvider),
          color: skin.accent,
          backgroundColor: skin.backgroundCard,
          child: sessions.isEmpty
              ? _EmptyState(
                  skin: skin,
                  icon: Icons.calendar_today_outlined,
                  title: 'Sin sesiones esta semana',
                  subtitle: '$weekFrom → $weekTo',
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: sessions.length,
                  itemBuilder: (context, i) {
                    final s = sessions[i] as Map<String, dynamic>;
                    return _SessionTile(
                        skin: skin, session: s, onTap: () => _openSession(s));
                  },
                ),
        );
      },
    );
  }

  // ── Vista CALENDARIO (mensual) ─────────────────────────────────
  Widget _buildCalendar(SkinConfig skin) {
    final state = ref.watch(planCalendarProvider);
    final notifier = ref.read(planCalendarProvider.notifier);

    // Con un día tocado → filtramos ese día; si no, agenda anclada en HOY.
    final filtered = _selectedDay == null
        ? null
        : state.sessions.where((s) {
            final raw =
                (s['scheduled_date'] ?? s['session_date']) as String? ?? '';
            final dp = raw.length >= 10 ? raw.substring(0, 10) : raw;
            return int.tryParse(dp.split('-').last) == _selectedDay;
          }).toList();
    final isCurrentMonth = _isCurrentMonth(state.month);

    return Column(
      children: [
        _MonthHeader(
          skin: skin,
          month: state.month,
          onPrev: () {
            setState(() => _selectedDay = null);
            notifier.goToPrevMonth();
          },
          onNext: () {
            setState(() => _selectedDay = null);
            notifier.goToNextMonth();
          },
        ),
        if (state.isLoading)
          Expanded(
            child: Center(child: CircularProgressIndicator(color: skin.accent)),
          )
        else if (state.error != null)
          Expanded(
            child: _ErrorView(
              skin: skin,
              msg: state.error!.replaceAll('Exception:', '').trim(),
              onRetry: () => notifier.load(),
            ),
          )
        else ...[
          _PlanCalendarGrid(
            skin: skin,
            month: state.month,
            byDay: state.byDay,
            selectedDay: _selectedDay,
            onDayTap: (d) => setState(
                () => _selectedDay = _selectedDay == d ? null : d),
          ),
          // Botón "Hoy": vuelve a la agenda del día actual (limpia filtro / mes).
          if (_selectedDay != null || !isCurrentMonth)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 12, top: 2),
                child: TextButton.icon(
                  onPressed: () {
                    setState(() => _selectedDay = null);
                    if (!isCurrentMonth) {
                      _calendarLoaded = true;
                      ref
                          .read(planCalendarProvider.notifier)
                          .goToCurrentMonth();
                    }
                  },
                  icon: Icon(Icons.today, size: 16, color: skin.accent),
                  label: Text('Hoy',
                      style: TextStyle(
                          color: skin.accent, fontWeight: FontWeight.w600)),
                ),
              ),
            )
          else
            const SizedBox(height: 8),
          Expanded(
            child: filtered != null
                ? (filtered.isEmpty
                    ? Center(
                        child: Text('Sin sesiones este día',
                            style: TextStyle(
                                color: skin.textMuted, fontSize: 14)),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final s = Map<String, dynamic>.from(filtered[i]);
                          return _SessionTile(
                              skin: skin,
                              session: s,
                              onTap: () => _openSession(s),
                              isToday: _isTodayDate(s));
                        },
                      ))
                : _AnchoredAgenda(
                    skin: skin,
                    sessions: state.sessions,
                    onTap: _openSession,
                  ),
          ),
        ],
      ],
    );
  }
}

// ── Agenda anclada en HOY ────────────────────────────────────────
// La sesión de hoy arranca arriba; se desliza ↑ para ver días pasados y
// ↓ para los próximos. Usa el anclado nativo (CustomScrollView.center),
// sin librerías: el sliver "centro" (hoy+futuro) empieza en el offset 0 y
// el de pasados crece hacia arriba (índice 0 = el pasado más reciente).
class _AnchoredAgenda extends StatelessWidget {
  final SkinConfig skin;
  final List<Map<String, dynamic>> sessions;
  final void Function(Map<String, dynamic>) onTap;
  const _AnchoredAgenda(
      {required this.skin, required this.sessions, required this.onTap});

  static String _dateOf(Map<String, dynamic> s) {
    final raw = (s['scheduled_date'] ?? s['session_date']) as String? ?? '';
    return raw.length >= 10 ? raw.substring(0, 10) : raw;
  }

  @override
  Widget build(BuildContext context) {
    final n = DateTime.now();
    final today =
        '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
    final all = sessions.map((s) => Map<String, dynamic>.from(s)).toList();
    final future = all.where((s) => _dateOf(s).compareTo(today) >= 0).toList()
      ..sort((a, b) => _dateOf(a).compareTo(_dateOf(b))); // asc: hoy primero
    final past = all.where((s) => _dateOf(s).compareTo(today) < 0).toList()
      ..sort((a, b) => _dateOf(b).compareTo(_dateOf(a))); // desc: reciente arriba

    if (future.isEmpty && past.isEmpty) {
      return Center(
        child: Text('Sin sesiones este mes',
            style: TextStyle(color: skin.textMuted, fontSize: 14)),
      );
    }

    Widget tile(Map<String, dynamic> s) => _SessionTile(
        skin: skin,
        session: s,
        onTap: () => onTap(s),
        isToday: _dateOf(s) == today);

    // Sin hoy/futuro → lista normal ascendente de los pasados.
    if (future.isEmpty) {
      final asc = [...past]..sort((a, b) => _dateOf(a).compareTo(_dateOf(b)));
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        itemCount: asc.length,
        itemBuilder: (_, i) => tile(asc[i]),
      );
    }

    const centerKey = ValueKey('planAgendaCenter');
    return CustomScrollView(
      center: centerKey,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, i) => tile(past[i]),
              childCount: past.length,
            ),
          ),
        ),
        SliverPadding(
          key: centerKey,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, i) => tile(future[i]),
              childCount: future.length,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Toggle Lista / Calendario ────────────────────────────────────
class _ViewToggle extends StatelessWidget {
  final SkinConfig skin;
  final _PlanView view;
  final ValueChanged<_PlanView> onChanged;
  const _ViewToggle(
      {required this.skin, required this.view, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget seg(_PlanView v, IconData icon, String label) {
      final sel = view == v;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(v),
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: sel ? skin.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 16, color: sel ? skin.background : skin.textMuted),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: sel ? skin.background : skin.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: skin.backgroundCard,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          seg(_PlanView.calendar, Icons.calendar_month_outlined, 'Calendario'),
          seg(_PlanView.list, Icons.view_agenda_outlined, 'Lista'),
        ],
      ),
    );
  }
}

// ── Cabecera de mes con navegación ───────────────────────────────
class _MonthHeader extends StatelessWidget {
  final SkinConfig skin;
  final DateTime month;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  const _MonthHeader(
      {required this.skin,
      required this.month,
      required this.onPrev,
      required this.onNext});

  static const _names = [
    '', 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: Icon(Icons.chevron_left, color: skin.textPrimary),
            onPressed: onPrev,
          ),
          Text(
            '${_names[month.month]} ${month.year}',
            style: TextStyle(
              color: skin.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          IconButton(
            icon: Icon(Icons.chevron_right, color: skin.textPrimary),
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

// ── Rejilla mensual (mismo estilo que Historial) ─────────────────
class _PlanCalendarGrid extends StatelessWidget {
  final SkinConfig skin;
  final DateTime month;
  final Map<int, List<Map<String, dynamic>>> byDay;
  final int? selectedDay;
  final ValueChanged<int> onDayTap;

  const _PlanCalendarGrid({
    required this.skin,
    required this.month,
    required this.byDay,
    required this.selectedDay,
    required this.onDayTap,
  });

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final startOffset = (firstDay.weekday - 1) % 7; // rejilla empieza en lunes
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
          Row(
            children: ['L', 'M', 'X', 'J', 'V', 'S', 'D']
                .map((d) => Expanded(
                      child: Center(
                        child: Text(
                          d,
                          style: TextStyle(
                            color: skin.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 6),
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
              final sessions = byDay[day] ?? const [];
              final isToday = month.year == today.year &&
                  month.month == today.month &&
                  day == today.day;
              final isSelected = selectedDay == day;

              Color? dotColor;
              if (sessions.isNotEmpty) {
                final hasCompleted =
                    sessions.any((s) => s['status'] == 'completed');
                final hasMissed = sessions.any((s) => s['status'] == 'missed');
                if (hasCompleted) {
                  dotColor = skin.success;
                } else if (hasMissed) {
                  dotColor = skin.error;
                } else {
                  dotColor = skin.warning; // programada / próxima
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
                        ? Border.all(
                            color: skin.accent.withValues(alpha: 0.5), width: 1)
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
                          fontWeight: sessions.isNotEmpty
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                      if (dotColor != null) ...[
                        const SizedBox(height: 2),
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                              color: dotColor, shape: BoxShape.circle),
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

// ── Estados auxiliares ───────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final SkinConfig skin;
  final IconData icon;
  final String title;
  final String subtitle;
  const _EmptyState(
      {required this.skin,
      required this.icon,
      required this.title,
      required this.subtitle});

  @override
  Widget build(BuildContext context) {
    // ListView para que RefreshIndicator siga funcionando aunque esté vacío
    return ListView(
      children: [
        const SizedBox(height: 120),
        Icon(icon, color: skin.textMuted, size: 48),
        const SizedBox(height: 12),
        Center(
          child: Text(title,
              style: TextStyle(color: skin.textPrimary, fontSize: 16)),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(subtitle,
              style: TextStyle(color: skin.textMuted, fontSize: 12)),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final SkinConfig skin;
  final String msg;
  final VoidCallback onRetry;
  const _ErrorView(
      {required this.skin, required this.msg, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, color: skin.error, size: 40),
            const SizedBox(height: 16),
            Text(
              'No se pudo cargar el plan',
              style: TextStyle(
                color: skin.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              msg,
              style: TextStyle(color: skin.textMuted, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: skin.accent,
                foregroundColor: skin.background,
              ),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Tarjeta de sesión (compartida por lista y calendario) ────────
class _SessionTile extends StatelessWidget {
  final SkinConfig skin;
  final Map<String, dynamic> session;
  final VoidCallback onTap;
  final bool isToday;
  const _SessionTile(
      {required this.skin,
      required this.session,
      required this.onTap,
      this.isToday = false});

  static String _fmtDate(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    try {
      final d = DateTime.parse(raw);
      const days = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
      const months = [
        'ene', 'feb', 'mar', 'abr', 'may', 'jun',
        'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
      ];
      return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]}';
    } catch (_) {
      return raw.length > 10 ? raw.substring(0, 10) : raw;
    }
  }

  static String _fmtDuration(dynamic raw) {
    if (raw == null) return '';
    final totalSec = (double.tryParse(raw.toString()) ?? 0) * 60;
    final m = totalSec ~/ 60;
    final s = totalSec.round() % 60;
    return s > 0 ? '${m}min ${s}s' : '${m}min';
  }

  @override
  Widget build(BuildContext context) {
    // La lista semanal manda 'session_date'; el calendario (getHistory) manda
    // 'scheduled_date'. Aceptamos ambos.
    final date =
        (session['session_date'] ?? session['scheduled_date']) as String? ?? '';
    final title = session['title'] as String? ?? 'Sesión';
    final status = session['status'] as String? ?? 'pending';
    final rawMin = session['planned_duration_min'];
    final esLibre = session['is_free_session'] == true;

    Color statusColor;
    String statusLabel;
    switch (status) {
      case 'completed':
        statusColor = skin.success;
        statusLabel = 'Completada';
      case 'missed':
        statusColor = skin.error;
        statusLabel = 'Perdida';
      case 'in_progress':
        statusColor = skin.warning;
        statusLabel = 'En progreso';
      case 'approved':
        statusColor = skin.accent;
        statusLabel = 'Aprobada';
      case 'rest':
        // Coincide con Inicio (que ya dice "Descanso"): un descanso no es una
        // sesión "Programada".
        statusColor = skin.textMuted;
        statusLabel = 'Descanso';
      default:
        statusColor = skin.textMuted;
        statusLabel = 'Programada';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(skin.cardRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 48,
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (isToday) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: skin.accent.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text('HOY',
                                style: TextStyle(
                                    color: skin.accent,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5)),
                          ),
                          const SizedBox(width: 6),
                        ],
                        if (esLibre) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFF22C55E)
                                  .withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(4),
                            ),
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
                            title,
                            style: TextStyle(
                              color: skin.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Fecha · duración  +  chip de estado (movido aquí abajo para
                    // que el título tenga el ancho completo y no se corte).
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            rawMin != null
                                ? '${_fmtDate(date)}  ·  ${_fmtDuration(rawMin)}'
                                : _fmtDate(date),
                            style:
                                TextStyle(color: skin.textMuted, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: statusColor.withValues(alpha: 0.35)),
                          ),
                          child: Text(
                            statusLabel,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, color: skin.textMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
