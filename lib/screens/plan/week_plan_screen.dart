import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/skin_provider.dart';
import '../../core/network/api_client.dart';

// ── Week Plan Screen ─────────────────────────────────────────────
// Muestra las sesiones de la semana actual.
// El atleta puede ver el plan del entrenador y navegar a cada sesión.

final _weekPlanProvider = FutureProvider<Map<String, dynamic>>((ref) async {
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
      ),
      body: plan.when(
        loading: () => Center(
          child: CircularProgressIndicator(color: skin.accent),
        ),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Error: $e', style: TextStyle(color: skin.error, fontSize: 12)),
          ),
        ),
        data: (data) {
          final sessions = (data['sessions'] as List?) ?? [];
          if (sessions.isEmpty) {
            return Center(
              child: Text(
                'Sin sesiones esta semana',
                style: TextStyle(color: skin.textMuted),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sessions.length,
            itemBuilder: (context, i) {
              final s = sessions[i] as Map<String, dynamic>;
              return _SessionTile(skin: skin, session: s,
                onTap: () => context.push('/session/${s['id']}'),
              );
            },
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
  const _SessionTile({required this.skin, required this.session, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final date   = session['session_date'] as String? ?? '';
    final title  = session['title'] as String? ?? 'Sesión';
    final status = session['status'] as String? ?? 'pending';
    final min    = (session['planned_duration_min'] as num?)?.toInt() ?? 0;

    final statusColor = status == 'completed' ? skin.success
        : status == 'in_progress' ? skin.warning : skin.textMuted;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 4,
          height: 40,
          decoration: BoxDecoration(
            color: statusColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        title: Text(title,
            style: TextStyle(color: skin.textPrimary, fontWeight: FontWeight.w600)),
        subtitle: Text('$date  ·  ${min}min',
            style: TextStyle(color: skin.textMuted, fontSize: 12)),
        trailing: Icon(Icons.chevron_right, color: skin.textMuted),
      ),
    );
  }
}
