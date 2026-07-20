import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/skin_provider.dart';
import '../../core/network/api_client.dart';

// FutureProvider con autoDispose → se reinicia cada vez que se abre la pantalla
final _weekPlanProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final api = ref.read(apiClientProvider);
  return api.getWeekPlan();
});

class WeekPlanScreen extends ConsumerWidget {
  const WeekPlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin = ref.watch(activeSkinProvider);
    final plan = ref.watch(_weekPlanProvider);

    return Scaffold(
      backgroundColor: skin.background,
      appBar: AppBar(
        title: const Text('Plan Semanal'),
        backgroundColor: skin.backgroundSecondary,
        foregroundColor: skin.textPrimary,
        elevation: 0,
      ),
      body: plan.when(
        loading: () => Center(
          child: CircularProgressIndicator(color: skin.accent),
        ),
        error: (e, _) => Center(
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
                  e.toString().replaceAll('Exception:', '').trim(),
                  style: TextStyle(color: skin.textMuted, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: () => ref.invalidate(_weekPlanProvider),
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
        ),
        data: (data) {
          final sessions = (data['sessions'] as List?) ?? [];
          final weekFrom = data['week_from'] as String? ?? '';
          final weekTo   = data['week_to']   as String? ?? '';

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(_weekPlanProvider),
            color: skin.accent,
            backgroundColor: skin.backgroundCard,
            child: sessions.isEmpty
                ? CustomScrollView(
                    slivers: [
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.calendar_today_outlined,
                                  color: skin.textMuted, size: 48),
                              const SizedBox(height: 12),
                              Text(
                                'Sin sesiones esta semana',
                                style: TextStyle(
                                    color: skin.textPrimary, fontSize: 16),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$weekFrom → $weekTo',
                                style: TextStyle(
                                    color: skin.textMuted, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: sessions.length,
                    itemBuilder: (context, i) {
                      final s = sessions[i] as Map<String, dynamic>;
                      return _SessionTile(
                        skin: skin,
                        session: s,
                        onTap: () {
                          final status = s['status'] as String? ?? '';
                          if (status == 'completed' || status == 'missed') {
                            context.push('/session/${s['id']}/summary');
                          } else {
                            context.push('/session/${s['id']}');
                          }
                        },
                      );
                    },
                  ),
          );
        },
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  final dynamic skin;
  final Map<String, dynamic> session;
  final VoidCallback onTap;
  const _SessionTile(
      {required this.skin, required this.session, required this.onTap});

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
    final date   = session['session_date'] as String? ?? '';
    final title  = session['title'] as String? ?? 'Sesión';
    final status = session['status'] as String? ?? 'pending';
    final rawMin = session['planned_duration_min'];

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
              // Barra de color lateral
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
                    Text(
                      title,
                      style: TextStyle(
                        color: skin.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      rawMin != null
                          ? '${_fmtDate(date)}  ·  ${_fmtDuration(rawMin)}'
                          : _fmtDate(date),
                      style: TextStyle(color: skin.textMuted, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Badge estado
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor.withValues(alpha: 0.35)),
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
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, color: skin.textMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
