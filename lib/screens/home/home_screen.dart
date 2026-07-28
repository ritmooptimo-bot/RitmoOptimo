import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/skin_provider.dart';
import '../../models/sport.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/network/api_client.dart';
import '../../core/network/pending_tracks.dart';
import '../../core/notifications/notification_service.dart';
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
    // Recorridos que no se pudieron subir en su momento (sin cobertura, servidor
    // caído): suben solos ahora. El entrenamiento del atleta no se pierde nunca.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PendingTracks.reintentarTodo(ref.read(apiClientProvider))
          .then((n) { if (n > 0) debugPrint('[PendingTracks] $n recorrido(s) subido(s) al abrir'); });
      _setupCheckinReminder();
    });
    Future.microtask(
      () => ref.read(dashboardProvider.notifier).load(),
    );
  }

  // Pide el permiso de notificaciones (una vez) y programa el recordatorio
  // diario del check-in de Bienestar. Solo aquí (el deportista ya está logueado).
  Future<void> _setupCheckinReminder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('notif_checkin_scheduled') == true) return;
      final granted = await NotificationService.requestPermission();
      if (granted) {
        await NotificationService.scheduleDailyCheckin(hour: 8);
        await prefs.setBool('notif_checkin_scheduled', true);
      }
    } catch (_) {/* si falla, no bloquea la app */}
  }

  // Si el check-in de HOY ya está hecho (por la app o por otro canal, p.ej.
  // WhatsApp), retira la notificación fija y re-arma la de mañana. Una vez al día.
  Future<void> _dismissTodayReminder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toIso8601String().split('T')[0];
      if (prefs.getString('notif_checkin_done_date') == today) return;
      await NotificationService.completedToday();
      await prefs.setString('notif_checkin_done_date', today);
    } catch (_) {/* si falla, no bloquea la app */}
  }

  @override
  Widget build(BuildContext context) {
    final skin      = ref.watch(activeSkinProvider);
    final dashboard = ref.watch(dashboardProvider);

    // Cuando el dashboard confirma que el check-in de hoy está hecho, retira la
    // notificación fija (aunque se haya rellenado desde otro canal).
    ref.listen(dashboardProvider, (_, next) {
      if (next.readiness?['doneToday'] == true) _dismissTodayReminder();
    });

    return Scaffold(
      backgroundColor: skin.background,
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/chat'),
        backgroundColor: skin.accent,
        foregroundColor: skin.background,
        tooltip: 'Chat con tu equipo',
        child: const Icon(Icons.chat_bubble_outline),
      ),
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

                // ── Progreso del mes ────────────────────────
                if (dashboard.monthProgress != null)
                  SliverToBoxAdapter(
                    child: _MonthProgressCard(
                      skin: skin,
                      progress: dashboard.monthProgress!,
                    ),
                  ),

                // ── Sesión de hoy ───────────────────────────
                SliverToBoxAdapter(
                  child: _TodaySessionCard(
                    skin: skin,
                    session: dashboard.todaySession,
                    onTap: dashboard.todaySession != null
                        ? () {
                            final id     = dashboard.todaySession!['id'] as String?;
                            final status = dashboard.todaySession!['status'] as String? ?? '';
                            if (id == null) return;
                            if (status == 'completed' || status == 'missed') {
                              context.push('/session/$id/summary');
                            } else {
                              context.push('/session/$id');
                            }
                          }
                        : null,
                  ),
                ),

                // ── Entrenar por mi cuenta ──────────────────
                SliverToBoxAdapter(
                  child: _FreeTrainingButton(skin: skin),
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

  // Chip de disciplina junto al nombre: el deporte del plan que lleva el atleta,
  // para que sepa en todo momento qué está entrenando.
  static (IconData, String) _disciplineMeta(String d) => switch (d) {
        'running'  => (Icons.directions_run, 'Running'),
        'trail'    => (Icons.terrain, 'Trail'),
        'ciclismo' => (Icons.directions_bike, 'Ciclismo'),
        'natacion' => (Icons.pool, 'Natación'),
        'triatlon' => (Icons.sports_score, 'Triatlón'),
        'fuerza'   => (Icons.fitness_center, 'Fuerza'),
        _          => (Icons.sports, d.isEmpty ? 'Plan' : '${d[0].toUpperCase()}${d.substring(1)}'),
      };

  Widget _disciplineChip(BuildContext context) {
    final d = (dashboard.discipline ?? '').toLowerCase().trim();
    if (d.isEmpty) return const SizedBox.shrink();
    final (icon, label) = _disciplineMeta(d);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: skin.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: skin.accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: skin.accent),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(color: skin.accent, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  // "Estado de hoy" (readiness) bajo el nombre: verde/ámbar/rojo o "haz tu check-in".
  Widget _readinessChip(BuildContext context) {
    final r = dashboard.readiness;
    if (r == null) return const SizedBox.shrink();
    final status = r['status'] as String? ?? 'pending';
    final Color color;
    final String text;
    final IconData icon;
    if (status == 'pending') {
      color = skin.textMuted;
      text = 'Haz tu check-in de hoy';
      icon = Icons.radio_button_unchecked;
    } else {
      switch (status) {
        case 'green':
          color = skin.success;
          break;
        case 'red':
          color = skin.error;
          break;
        default:
          color = skin.warning;
      }
      text = r['label'] as String? ?? 'Estado de hoy';
      icon = Icons.circle;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: InkWell(
        onTap: () => _showReadinessInfo(context, r),
        borderRadius: BorderRadius.circular(20),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 12),
            const SizedBox(width: 6),
            Flexible(
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 4),
            Icon(Icons.info_outline,
                color: color.withValues(alpha: 0.6), size: 13),
          ],
        ),
      ),
    );
  }

  void _showReadinessInfo(BuildContext context, Map<String, dynamic> r) {
    final status = r['status'] as String? ?? 'pending';
    final title = status == 'pending'
        ? 'Tu check-in de hoy'
        : (r['label'] as String? ?? 'Estado de hoy');
    final body = status == 'pending'
        ? 'Aún no has registrado tu bienestar de hoy. Hazlo en la pestaña Bienestar '
            '(2 min), a ser posible antes de entrenar: así tu plan se adapta a cómo '
            'estás. Se hace una vez al día.'
        : (r['advice'] as String? ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: skin.backgroundSecondary,
        title: Text(title,
            style: TextStyle(
                color: skin.textPrimary, fontWeight: FontWeight.w700)),
        content: Text(body,
            style: TextStyle(color: skin.textSecondary, height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Entendido', style: TextStyle(color: skin.accent)),
          ),
        ],
      ),
    );
  }

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
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        (dashboard.athleteName == null ||
                                dashboard.athleteName!.trim().isEmpty)
                            ? 'Atleta'
                            : dashboard.athleteName!.trim().split(RegExp(r'\s+')).first,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: skin.textPrimary,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if ((dashboard.discipline ?? '').trim().isNotEmpty) ...[
                      const SizedBox(width: 8),
                      _disciplineChip(context),
                    ],
                  ],
                ),
                _readinessChip(context),
              ],
            ),
          ),
          // Alerta badge — PULSABLE: abre la lista de avisos del deportista
          if (dashboard.pendingAlerts > 0)
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _showAlerts(context, skin),
                child: Container(
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
                      Icon(Icons.keyboard_arrow_down_rounded,
                          color: skin.warning, size: 16),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showAlerts(BuildContext context, SkinConfig skin) {
    showModalBottomSheet(
      context: context,
      backgroundColor: skin.backgroundCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _AlertsSheet(skin: skin),
    );
  }
}

// ── Hoja de avisos del deportista (badge ⚠️ pulsable) ───────────
class _AlertsSheet extends StatefulWidget {
  final SkinConfig skin;
  const _AlertsSheet({required this.skin});
  @override
  State<_AlertsSheet> createState() => _AlertsSheetState();
}

class _AlertsSheetState extends State<_AlertsSheet> {
  late final Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiClient().getAlerts();
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: skin.textMuted.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: skin.warning, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Avisos de tu entrenamiento',
                    style: TextStyle(
                        color: skin.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Cosas que hemos visto en tus sesiones. Nada urgente salvo que te lo digamos.',
              style: TextStyle(color: skin.textMuted, fontSize: 12.5, height: 1.3),
            ),
            const SizedBox(height: 16),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _future,
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                        child: CircularProgressIndicator(color: skin.accent)),
                  );
                }
                if (snap.hasError) {
                  return _msg(skin,
                      'No pudimos cargar tus avisos. Prueba de nuevo en un momento.');
                }
                final alerts = snap.data ?? [];
                if (alerts.isEmpty) {
                  return _msg(skin,
                      'No tienes avisos ahora mismo. ¡Buen trabajo! 🎉');
                }
                return Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: alerts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) =>
                        _AlertCard(skin: skin, alert: alerts[i]),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _msg(SkinConfig skin, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: skin.textSecondary, fontSize: 14),
          ),
        ),
      );
}

class _AlertCard extends StatelessWidget {
  final SkinConfig skin;
  final Map<String, dynamic> alert;
  const _AlertCard({required this.skin, required this.alert});

  @override
  Widget build(BuildContext context) {
    final isCritical = alert['level'] == 'critical';
    final color = isCritical ? skin.error : skin.warning;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                  isCritical
                      ? Icons.error_outline_rounded
                      : Icons.warning_amber_rounded,
                  color: color,
                  size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  alert['title']?.toString() ?? 'Aviso',
                  style: TextStyle(
                      color: skin.textPrimary,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700),
                ),
              ),
              if (alert['date'] != null)
                Text(
                  alert['date'].toString(),
                  style: TextStyle(color: skin.textMuted, fontSize: 11.5),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            alert['message']?.toString() ?? '',
            style: TextStyle(
                color: skin.textSecondary, fontSize: 13, height: 1.35),
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

  // Explica en lenguaje llano qué es CTL/ATL/TSB. tsbColor se pasa para
  // que la sigla TSB use el mismo color que la tarjeta (Forma/Neutro/Fatigado).
  void _mostrarInfo(BuildContext context, Color tsbColor) {
    Widget item(String sigla, String nombre, String desc, Color color) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    sigla,
                    style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    nombre,
                    style: TextStyle(
                        color: skin.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              desc,
              style: TextStyle(
                  color: skin.textSecondary, fontSize: 13, height: 1.35),
            ),
          ],
        ),
      );
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: skin.backgroundCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(skin.cardRadius)),
        title: Text(
          'Tu forma deportiva',
          style: TextStyle(
              color: skin.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              item('CTL', 'Forma física',
                  'Tu nivel de fondo. Resume la carga de entrenamiento que has acumulado en las últimas ~6 semanas. Sube poco a poco con la constancia: cuanto más alto, más en forma estás.',
                  skin.accent),
              item('ATL', 'Fatiga',
                  'Tu cansancio reciente. Resume la carga de los últimos ~7 días. Sube rápido cuando entrenas fuerte y baja al descansar.',
                  skin.warning),
              item('TSB', 'Frescura',
                  'El equilibrio entre forma y fatiga (CTL − ATL). En positivo estás fresco y descansado, ideal para competir. En negativo estás fatigado: tu cuerpo todavía está asimilando la carga.',
                  tsbColor),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Entendido',
                style: TextStyle(
                    color: skin.accent, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
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
              // Título + icono de info: CTL/ATL/TSB no dicen nada a simple vista,
              // así que un toque en la (i) explica qué es cada uno.
              Row(
                children: [
                  Text(
                    'Forma Deportiva',
                    style: TextStyle(
                      color: skin.textMuted,
                      fontSize: 11,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => _mostrarInfo(context, tsbColor),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(Icons.info_outline,
                          size: 15, color: skin.textMuted),
                    ),
                  ),
                ],
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
                  const SizedBox(width: 12),
                  // El chip de estado ocupa el espacio restante, se alinea a la
                  // derecha y se encoge si hiciera falta → nunca desborda (antes
                  // "Fatigado" se cortaba contra el borde con un TSB de -25.4).
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Container(
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
                      ),
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

// ── Month Progress Card ──────────────────────────────────────────
class _MonthProgressCard extends StatelessWidget {
  final SkinConfig skin;
  final Map<String, dynamic> progress;
  const _MonthProgressCard({required this.skin, required this.progress});

  static int _i(dynamic v) {
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static double _d(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }

  // Explica el premio de constancia al tocar la (i): 100% del plan → descuento.
  void _infoPremio(BuildContext context, double? discount) {
    final d = discount?.toStringAsFixed(2).replaceAll('.', ',');
    Widget bullet(String t) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('•  ',
                  style: TextStyle(color: skin.textSecondary, fontSize: 13.5)),
              Expanded(
                child: Text(t,
                    style: TextStyle(
                        color: skin.textSecondary,
                        fontSize: 13.5,
                        height: 1.35)),
              ),
            ],
          ),
        );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: skin.backgroundCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(skin.cardRadius)),
        title: Text('Premio de constancia',
            style: TextStyle(
                color: skin.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cada mes que completas TODOS los entrenos de tu plan, se te aplica un descuento en tu cuota.',
              style: TextStyle(
                  color: skin.textSecondary, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 14),
            bullet('El descanso cuenta como día cumplido.'),
            bullet('Los entrenos libres no penalizan.'),
            bullet('Solo pierdes el premio si dejas sin hacer un entreno del plan.'),
            if (d != null) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: skin.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Este mes: hasta −$d€ de descuento si lo completas.',
                  style: TextStyle(
                      color: skin.accent,
                      fontSize: 14,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Entendido', style: TextStyle(color: skin.accent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Adherencia por DÍAS del mes (la calcula el backend): completar las sesiones
    // creadas NO da 100% falso; el 100% solo llega al cerrar el mes sin fallar un
    // entreno del plan. El descanso cuenta; lo libre nunca penaliza.
    final pct       = _d(progress['pct']).clamp(0.0, 1.0);
    final fulfilled = _i(progress['fulfilled_days']);
    final daysMonth = _i(progress['days_in_month']);
    final done      = _i(progress['required_done']);
    final total     = _i(progress['required_total']);
    final km        = _d(progress['total_distance_km']);
    final reward    = (progress['reward'] as String?) ?? 'en_curso';
    final discount  = progress['discount_eur']  == null ? null : _d(progress['discount_eur']);
    final committed = progress['committed_eur'] == null ? null : _d(progress['committed_eur']);

    final bool conseguido = reward == 'conseguido';
    final bool perdido    = reward == 'perdido';
    final Color mainColor = conseguido
        ? skin.success
        : perdido
            ? skin.textMuted
            : skin.accent;

    // Badge de estado del premio de constancia
    String? badge;
    Color badgeColor = mainColor;
    if (conseguido) {
      badge = '¡Premio conseguido! 🏆';
      badgeColor = skin.success;
    } else if (reward == 'en_curso') {
      badge = 'Vas en regla';
      badgeColor = skin.accent;
    } else if (perdido) {
      badge = 'Sin premio este mes';
      badgeColor = skin.textMuted;
    } // sin_plan → sin badge

    // Línea inferior: el incentivo económico (o motivación si aún no hay tarifa)
    String bottom;
    if (discount != null) {
      final d = discount.toStringAsFixed(2).replaceAll('.', ',');
      final cp = committed?.toStringAsFixed(2).replaceAll('.', ',');
      if (conseguido) {
        bottom = '¡Has ganado -$d€ este mes! 🎉';
      } else if (perdido) {
        bottom = 'El premio de -$d€ vuelve el mes que viene.';
      } else {
        bottom = cp != null
            ? 'Completa el mes y pagas $cp€ (ahorras $d€)'
            : 'Completa el mes y ahorras $d€';
      }
    } else {
      if (conseguido) {
        bottom = '¡Mes completado! Constancia de 10 💪';
      } else if (perdido) {
        bottom = 'Este mes no llegas al premio, pero cada entreno suma.';
      } else {
        bottom = 'Completa los entrenos del plan y baja tu cuota.';
      }
    }

    Widget stat(String value, String label, Color color) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(color: skin.textMuted, fontSize: 10.5),
                ),
              ),
            ],
          ),
        );

    Widget divider() => Container(
          width: 1,
          height: 40,
          color: skin.border,
          margin: const EdgeInsets.symmetric(horizontal: 12),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          color: skin.backgroundCard,
          borderRadius: BorderRadius.circular(skin.cardRadius),
          border: Border.all(
            color: conseguido ? skin.success.withValues(alpha: 0.6) : skin.border,
            width: conseguido ? 1.5 : 1,
          ),
          boxShadow: conseguido
              ? [BoxShadow(color: skin.success.withValues(alpha: 0.15), blurRadius: 16)]
              : null,
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabecera
            Row(
              children: [
                Text(
                  'PROGRESO DEL MES',
                  style: TextStyle(
                    color: skin.textMuted,
                    fontSize: 10,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                // (i): explica el premio de constancia (100% del plan → descuento)
                GestureDetector(
                  onTap: () => _infoPremio(context, discount),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(Icons.info_outline,
                        size: 14, color: skin.textMuted),
                  ),
                ),
                // El badge se alinea a la derecha y se ESCALA para caber SIEMPRE
                // entero — antes se cortaba a "Si...".
                if (badge != null)
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: badgeColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            badge,
                            maxLines: 1,
                            style: TextStyle(
                              color: badgeColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),

            // Tres métricas: % del mes · sesiones del plan · km del mes
            Row(
              children: [
                stat('${(pct * 100).round()}%', '$fulfilled/$daysMonth días', mainColor),
                divider(),
                stat('$done/$total', 'sesiones plan', skin.textPrimary),
                divider(),
                stat(
                  km >= 1000 ? '${(km / 1000).toStringAsFixed(1)}k' : km.toStringAsFixed(1),
                  'km del mes',
                  skin.accentSecondary,
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Barra del mes (el color indica el estado del premio)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 7,
                backgroundColor: skin.border.withValues(alpha: 0.5),
                valueColor: AlwaysStoppedAnimation<Color>(mainColor),
              ),
            ),
            const SizedBox(height: 8),

            // Incentivo económico / motivación
            Row(
              children: [
                Icon(
                  conseguido
                      ? Icons.emoji_events_outlined
                      : perdido
                          ? Icons.info_outline
                          : Icons.savings_outlined,
                  size: 14,
                  color: perdido ? skin.textMuted : mainColor,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    bottom,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: perdido ? skin.textMuted : skin.textSecondary,
                      fontSize: 12,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Today Session Card ───────────────────────────────────────────
class _TodaySessionCard extends StatelessWidget {
  final SkinConfig skin;
  final Map<String, dynamic>? session;
  final VoidCallback? onTap;
  const _TodaySessionCard(
      {required this.skin, this.session, this.onTap});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(skin.cardRadius);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: skin.backgroundCard,
            borderRadius: radius,
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
                    : _SessionContent(skin: skin, session: session!, onStart: onTap),
              ),
            ],
          ),
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

  static String  _sportLabel(String? raw) => Sport.fromApi(raw).label;
  static IconData _sportIcon(String? raw)  => Sport.fromApi(raw).icon;

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
      case 'missed':
        // Antes caía en 'default' → "Pendiente": una sesión no realizada salía
        // como pendiente en Inicio pero "Perdida" en el Plan (misma sesión, dos
        // etiquetas). Ahora coincide con el Plan.
        statusColor = skin.error;
        statusText  = 'Perdida';
      case 'rest':
        statusColor = skin.textMuted;
        statusText  = 'Descanso';
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
        if (status != 'completed' && status != 'in_progress' && status != 'missed') ...[
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

// ── Entrenar por mi cuenta ───────────────────────────────────────
// Si hoy no le apetece lo planificado o simplemente sale a hacer otra cosa, que
// pueda registrarlo. Un entreno sin registrar es un entreno que el entrenador no
// puede tener en cuenta.
class _FreeTrainingButton extends StatelessWidget {
  final SkinConfig skin;
  const _FreeTrainingButton({required this.skin});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: InkWell(
        onTap: () => context.push('/free-session'),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: skin.backgroundCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: skin.border),
          ),
          child: Row(
            children: [
              Icon(Icons.add_circle_outline, color: skin.accent, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Entrenar por mi cuenta',
                      style: TextStyle(
                        color: skin.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Carrera, trail, bici, fuerza o natación',
                      style: TextStyle(color: skin.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: skin.textMuted, size: 20),
            ],
          ),
        ),
      ),
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
