import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/skin_provider.dart';
import '../../providers/workout_provider.dart';
import '../../config/skins/skin_config.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(dashboardProvider.notifier).load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final skin      = ref.watch(activeSkinProvider);
    final dashboard = ref.watch(dashboardProvider);

    return Scaffold(
      backgroundColor: skin.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(dashboardProvider.notifier).load(),
          color: skin.accent,
          backgroundColor: skin.backgroundCard,
          child: CustomScrollView(
            slivers: [
              // ── Header ────────────────────────────────────
              SliverToBoxAdapter(
                child: _Header(skin: skin, dashboard: dashboard),
              ),

              if (dashboard.isLoading)
                SliverFillRemaining(
                  hasScrollBody: false,
                  fillOverscroll: false,
                  child: Container(
                    color: skin.background,
                    child: Center(
                      child: CircularProgressIndicator(color: skin.accent),
                    ),
                  ),
                )
              else if (dashboard.error != null && dashboard.todaySession == null && dashboard.fitness == null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  fillOverscroll: false,
                  child: Container(
                    color: skin.background,
                    child: Center(
                      child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.wifi_off_rounded, color: skin.error, size: 40),
                          const SizedBox(height: 12),
                          Text(
                            'No se pudo cargar el panel',
                            style: TextStyle(color: skin.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: skin.error.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: skin.error.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              dashboard.error!.replaceAll('Exception: ', ''),
                              style: TextStyle(color: skin.error, fontSize: 11),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            onPressed: () => ref.read(dashboardProvider.notifier).load(),
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('Reintentar'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                )
              else ...[
                // ── Forma deportiva (CTL/ATL/TSB) ──────────
                if (dashboard.fitness != null)
                  SliverToBoxAdapter(
                    child: _FitnessCard(skin: skin, fitness: dashboard.fitness!),
                  ),

                // ── Sesión de hoy ───────────────────────────
                SliverToBoxAdapter(
                  child: _TodaySessionCard(
                    skin: skin,
                    session: dashboard.todaySession,
                    onStart: dashboard.todaySession != null
                        ? () => context.push(
                            '/session/${dashboard.todaySession!['id']}')
                        : null,
                  ),
                ),

                // ── Bienestar ───────────────────────────────
                if (dashboard.latestWellness != null)
                  SliverToBoxAdapter(
                    child: _WellnessCard(
                      skin: skin,
                      wellness: dashboard.latestWellness!,
                    ),
                  ),

                const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Header ───────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  final SkinConfig skin;
  final DashboardState dashboard;
  const _Header({required this.skin, required this.dashboard});

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Buenos días'
        : hour < 19
            ? 'Buenas tardes'
            : 'Buenas noches';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting,
                  style: TextStyle(color: skin.textMuted, fontSize: 13),
                ),
                Text(
                  'Atleta',
                  style: TextStyle(
                    color: skin.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          // Alerta badge
          if (dashboard.pendingAlerts > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: skin.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: skin.warning.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: skin.warning, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    '${dashboard.pendingAlerts}',
                    style: TextStyle(
                        color: skin.warning,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Fitness Card (CTL/ATL/TSB) ──────────────────────────────────
class _FitnessCard extends StatelessWidget {
  final SkinConfig skin;
  final Map<String, dynamic> fitness;
  const _FitnessCard({required this.skin, required this.fitness});

  static double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num)  return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final ctl = _toDouble(fitness['ctl']);
    final atl = _toDouble(fitness['atl']);
    final tsb = _toDouble(fitness['tsb']);

    Color tsbColor;
    String tsbLabel;
    if (tsb > 5) {
      tsbColor = skin.success;
      tsbLabel = 'Forma';
    } else if (tsb >= -10) {
      tsbColor = skin.warning;
      tsbLabel = 'Neutro';
    } else {
      tsbColor = skin.error;
      tsbLabel = 'Fatigado';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Forma Deportiva',
                style: TextStyle(
                  color: skin.textMuted,
                  fontSize: 11,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _Metric(label: 'CTL', value: ctl.toStringAsFixed(1),
                      color: skin.accent, skin: skin),
                  const SizedBox(width: 24),
                  _Metric(label: 'ATL', value: atl.toStringAsFixed(1),
                      color: skin.warning, skin: skin),
                  const SizedBox(width: 24),
                  _Metric(label: 'TSB', value: tsb.toStringAsFixed(1),
                      color: tsbColor, skin: skin),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: tsbColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      tsbLabel,
                      style: TextStyle(
                          color: tsbColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final SkinConfig skin;
  const _Metric(
      {required this.label,
      required this.value,
      required this.color,
      required this.skin});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(color: skin.textMuted, fontSize: 10,
                letterSpacing: 1.2)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            fontFamily: skin.useMonoForData ? skin.fontFamilyMono : skin.fontFamily,
          ),
        ),
      ],
    );
  }
}

// ── Today Session Card ───────────────────────────────────────────
class _TodaySessionCard extends StatelessWidget {
  final SkinConfig skin;
  final Map<String, dynamic>? session;
  final VoidCallback? onStart;
  const _TodaySessionCard(
      {required this.skin, this.session, this.onStart});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          color: skin.backgroundCard,
          borderRadius: BorderRadius.circular(skin.cardRadius),
          border: Border.all(
            color: session != null ? skin.accent.withValues(alpha: 0.6) : skin.border,
            width: session != null ? 1.5 : 1,
          ),
          boxShadow: session != null ? [
            BoxShadow(
              color: skin.accent.withValues(alpha: 0.12),
              blurRadius: 16,
              spreadRadius: 0,
            )
          ] : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (session != null)
              Container(
                height: 3,
                decoration: BoxDecoration(
                  color: skin.accent,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(skin.cardRadius),
                    topRight: Radius.circular(skin.cardRadius),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: session == null
                  ? _EmptySession(skin: skin)
                  : _SessionContent(skin: skin, session: session!, onStart: onStart),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptySession extends StatelessWidget {
  final SkinConfig skin;
  const _EmptySession({required this.skin});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(Icons.check_circle_outline, color: skin.success, size: 40),
        const SizedBox(height: 8),
        Text(
          'Sin sesión programada hoy',
          style: TextStyle(color: skin.textSecondary, fontSize: 15),
        ),
        const SizedBox(height: 4),
        Text(
          'Día de descanso activo',
          style: TextStyle(color: skin.textMuted, fontSize: 12),
        ),
      ],
    );
  }
}

class _SessionContent extends StatelessWidget {
  final SkinConfig skin;
  final Map<String, dynamic> session;
  final VoidCallback? onStart;
  const _SessionContent({required this.skin, required this.session, this.onStart});

  static String _sportLabel(String? raw) {
    if (raw == null || raw.isEmpty) return 'Entrenamiento';
    switch (raw.toLowerCase()) {
      case 'running': case 'carrera': return 'Carrera';
      case 'cycling': case 'bici':    return 'Ciclismo';
      case 'swimming':                return 'Natación';
      case 'strength': case 'fuerza': return 'Fuerza';
      case 'base':                    return 'Rodaje base';
      case 'recovery': case 'recuperacion': return 'Recuperación';
      default: return raw[0].toUpperCase() + raw.substring(1);
    }
  }

  static IconData _sportIcon(String? raw) {
    switch (raw?.toLowerCase()) {
      case 'cycling': case 'bici': return Icons.directions_bike;
      case 'swimming':             return Icons.pool;
      case 'strength': case 'fuerza': return Icons.fitness_center;
      default:                     return Icons.directions_run;
    }
  }

  @override
  Widget build(BuildContext context) {
    final status  = session['status'] as String? ?? 'pending';
    final title   = session['title']  as String? ?? 'Sesión de entrenamiento';
    final sport   = session['sport']  as String?;
    final rawMin  = session['planned_duration_min'];
    final minutes = rawMin is num
        ? rawMin.toInt()
        : int.tryParse(rawMin?.toString() ?? '') ?? 0;

    Color statusColor;
    String statusText;
    switch (status) {
      case 'completed':
        statusColor = skin.success;
        statusText  = 'Completada';
      case 'in_progress':
        statusColor = skin.warning;
        statusText  = 'En progreso';
      case 'scheduled':
        statusColor = skin.accent;
        statusText  = 'Programada';
      default:
        statusColor = skin.accent;
        statusText  = 'Pendiente';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'SESIÓN DE HOY',
              style: TextStyle(
                color: skin.accent,
                fontSize: 10,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: statusColor.withValues(alpha: 0.4)),
              ),
              child: Text(
                statusText,
                style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          title,
          style: TextStyle(
            color: skin.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(_sportIcon(sport), color: skin.accentSecondary, size: 15),
            const SizedBox(width: 5),
            Text(
              _sportLabel(sport),
              style: TextStyle(color: skin.textSecondary, fontSize: 13),
            ),
            const SizedBox(width: 16),
            Icon(Icons.timer_outlined, color: skin.accentSecondary, size: 15),
            const SizedBox(width: 5),
            Text(
              '${minutes} min',
              style: TextStyle(color: skin.textSecondary, fontSize: 13),
            ),
          ],
        ),
        if (status == 'pending' || status == 'scheduled' || status == 'approved') ...[
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onStart,
              style: ElevatedButton.styleFrom(
                backgroundColor: skin.accent,
                foregroundColor: skin.background,
                disabledBackgroundColor: skin.accent,
                disabledForegroundColor: skin.background,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('Iniciar sesión',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Wellness Card ────────────────────────────────────────────────
class _WellnessCard extends StatelessWidget {
  final SkinConfig skin;
  final Map<String, dynamic> wellness;
  const _WellnessCard({required this.skin, required this.wellness});

  @override
  Widget build(BuildContext context) {
    final fatigue    = (wellness['fatigue_level']  as num?)?.toInt() ?? 0;
    final motivation = (wellness['motivation']     as num?)?.toInt() ?? 0;
    final sleep      = (wellness['sleep_hours'] as num?)?.toDouble() ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'BIENESTAR',
                style: TextStyle(
                    color: skin.textMuted,
                    fontSize: 10,
                    letterSpacing: 1.5),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _WellnessItem(
                      label: 'Fatiga',
                      value: '$fatigue/5',
                      icon: Icons.battery_charging_full,
                      skin: skin),
                  const SizedBox(width: 20),
                  _WellnessItem(
                      label: 'Motivación',
                      value: '$motivation/5',
                      icon: Icons.bolt,
                      skin: skin),
                  const SizedBox(width: 20),
                  _WellnessItem(
                      label: 'Sueño',
                      value: '${sleep.toStringAsFixed(1)}h',
                      icon: Icons.bedtime_outlined,
                      skin: skin),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WellnessItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final SkinConfig skin;
  const _WellnessItem(
      {required this.label,
      required this.value,
      required this.icon,
      required this.skin});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: skin.accentSecondary, size: 20),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                color: skin.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 14)),
        Text(label,
            style: TextStyle(color: skin.textMuted, fontSize: 10)),
      ],
    );
  }
}
