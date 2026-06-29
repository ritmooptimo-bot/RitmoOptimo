import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/skin_provider.dart';
import '../../providers/workout_provider.dart';
import '../../config/skins/skin_config.dart';
import '../../core/network/api_client.dart';
import '../../core/ble/ble_service.dart';
import '../../core/gps/gps_service.dart';

class SessionScreen extends ConsumerStatefulWidget {
  final String sessionId;
  const SessionScreen({super.key, required this.sessionId});

  @override
  ConsumerState<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends ConsumerState<SessionScreen> {
  Timer? _timer;
  bool _loadingSession = true; // true hasta que loadSession() devuelva datos

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        await ref.read(activeSessionProvider.notifier).loadSession(widget.sessionId);
        if (mounted) setState(() => _loadingSession = false);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      ref.read(activeSessionProvider.notifier).tickSecond();
    });
  }

  // Abre el scanner BLE. Puede llamarse antes o durante la sesión.
  Future<void> _openBleScan() async {
    final notifier = ref.read(activeSessionProvider.notifier);
    final device   = await context.push<BluetoothDevice?>(
      '/ble-scan/${widget.sessionId}',
    );
    if (device != null && mounted) {
      await notifier.connectBLE(device);
    }
  }

  Future<void> _onStart() async {
    if (_timer != null) return; // evitar doble inicio

    final notifier = ref.read(activeSessionProvider.notifier);
    final ble      = ref.read(bleServiceProvider);
    final gps      = ref.read(gpsServiceProvider);

    // 1. BLE — solo abrir scanner si no hay sensor ya conectado
    if (!ble.isConnected) {
      await _openBleScan();
    }

    // 2. GPS — pedir permiso y empezar track
    final gpsOk = await gps.requestPermission();
    if (gpsOk) notifier.startGPS();

    // 3. Marcar como activa e iniciar timer ANTES del API call.
    //    El FINALIZAR ya aparece aunque haya problema de red.
    notifier.markAsRunning();
    _startTimer();

    // 4. Sincronizar con backend (no bloqueante — la sesión ya corre localmente)
    try {
      await notifier.startSession(widget.sessionId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sesión activa. Sin sincronización con servidor.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _onFinish() async {
    final skin    = ref.read(activeSkinProvider);
    final elapsed = ref.read(activeSessionProvider).elapsedSeconds;
    final isShort = elapsed < 120; // menos de 2 minutos

    // Siempre pedir confirmación — aviso extra si la sesión fue muy corta
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: skin.backgroundCard,
        title: Text(
          isShort ? '⚠️  Sesión muy corta' : '¿Finalizar sesión?',
          style: TextStyle(color: skin.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: Text(
          isShort
              ? 'Solo llevas ${elapsed}s entrenando.\n¿Estás seguro de que quieres finalizar ya?'
              : 'Llevas ${_formatTime(elapsed)} entrenando.\n¿Confirmas el fin de la sesión?',
          style: TextStyle(color: skin.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Continuar entrenando', style: TextStyle(color: skin.accent)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: skin.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Finalizar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    _timer?.cancel();

    final notifier = ref.read(activeSessionProvider.notifier);
    final api      = ref.read(apiClientProvider);
    final session  = ref.read(activeSessionProvider);

    final track = notifier.stopGPS();
    if (track.points.isNotEmpty) {
      api.postGPSTrack(widget.sessionId, track.toBackendPayload())
          .catchError((e) => debugPrint('[GPS] Error upload: $e'));
    }

    if (session.bleConnected) await notifier.disconnectBLE();

    if (mounted) {
      context.pushReplacement('/session/${widget.sessionId}/complete');
    }
  }

  Future<void> _onRedo() async {
    final skin = ref.read(activeSkinProvider);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: skin.backgroundCard,
        title: Text('Sesión ya completada',
            style: TextStyle(color: skin.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text(
          'Esta sesión ya está registrada como completada por tu entrenador.\n\n'
          'Si la realizas de nuevo, los nuevos datos de entrenamiento reemplazarán a los anteriores.\n\n'
          '¿Quieres continuar?',
          style: TextStyle(color: skin.textSecondary, height: 1.55),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancelar', style: TextStyle(color: skin.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Realizar de nuevo'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _onStart();
  }

  String _formatTime(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final skin    = ref.watch(activeSkinProvider);
    final session = ref.watch(activeSessionProvider);

    final sessionStatus  = session.session?['status'] as String? ?? '';
    final isCompleted    = !_loadingSession && sessionStatus == 'completed' && !session.isRunning;
    final isPreStart     = !_loadingSession && !session.isRunning && !isCompleted;

    return Scaffold(
      backgroundColor: skin.background,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: skin.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          isCompleted        ? 'COMPLETADA'
              : session.isRunning ? 'EN CURSO'
              : 'SESIÓN',
          style: TextStyle(
              color: isCompleted ? skin.success : skin.textPrimary,
              letterSpacing: 2,
              fontSize: 14),
        ),
        backgroundColor: skin.backgroundSecondary,
        actions: [
          if (session.isRunning)
            TextButton(
              onPressed: _onFinish,
              child: Text('FINALIZAR',
                  style: TextStyle(
                      color: skin.error, fontWeight: FontWeight.w700, letterSpacing: 1)),
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Header: timer (en curso) o resumen (completada) ──
          _SessionHeader(
            skin: skin,
            session: session,
            elapsed: _formatTime(session.elapsedSeconds),
            isCompleted: isCompleted,
          ),

          // ── Banner "Completada" con datos reales ──────────
          if (isCompleted)
            _CompletedSummaryBanner(skin: skin, sessionData: session.session!),

          // ── Estado sensores — solo cuando no está completada ─
          if (!isCompleted) ...[
            _SensorStatusRow(skin: skin, session: session, onConnectBle: _openBleScan),
            const SizedBox(height: 8),
          ],

          // ── Bloques del plan ─────────────────────────────
          Expanded(
            child: _SessionBlocks(
              planned: session.session?['planned_structure'] as List<dynamic>? ?? [],
              elapsed: session.elapsedSeconds,
              skin: skin,
            ),
          ),

          // ── Área inferior: botón según estado ────────────
          if (_loadingSession)
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: null,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2,
                              color: skin.textMuted)),
                      const SizedBox(width: 12),
                      Text('Cargando sesión...',
                          style: TextStyle(color: skin.textMuted)),
                    ],
                  ),
                ),
              ),
            )
          else if (isCompleted)
            _CompletedFooter(skin: skin, onRedo: _onRedo)
          else if (session.isRunning)
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: skin.error, foregroundColor: Colors.white),
                  onPressed: _onFinish,
                  child: const Text('FINALIZAR SESIÓN',
                      style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 2)),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: isPreStart ? _onStart : null,
                  child: const Text('COMENZAR',
                      style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 2)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Session Header (timer + FC + ritmo) ─────────────────────────

class _SessionHeader extends StatelessWidget {
  final SkinConfig skin;
  final ActiveSessionState session;
  final String elapsed;
  final bool isCompleted;
  const _SessionHeader(
      {required this.skin, required this.session, required this.elapsed,
       this.isCompleted = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      color: skin.backgroundSecondary,
      child: Column(
        children: [
          if (isCompleted)
            Icon(Icons.check_circle_outline, size: 56, color: skin.success)
          else
            Text(
              elapsed,
              style: TextStyle(
                fontFamily: skin.fontFamilyMono,
                fontSize: 56,
                fontWeight: FontWeight.w700,
                color: session.isRunning ? skin.accent : skin.textMuted,
                letterSpacing: 4,
              ),
            ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _DataBadge(
                label: 'FC',
                value: session.currentHR != null
                    ? '${session.currentHR}'
                    : '--',
                unit: 'bpm',
                icon: Icons.favorite,
                color: skin.error,
                skin: skin,
              ),
              const SizedBox(width: 32),
              _DataBadge(
                label: 'RITMO',
                value: session.currentPace != null && session.currentPace! > 0
                    ? _formatPace(session.currentPace!)
                    : '--:--',
                unit: '/km',
                icon: Icons.speed,
                color: skin.accent,
                skin: skin,
              ),
              const SizedBox(width: 32),
              _DataBadge(
                label: 'DIST',
                value: session.totalDistanceM > 0
                    ? (session.totalDistanceM / 1000).toStringAsFixed(2)
                    : '0.00',
                unit: 'km',
                icon: Icons.route,
                color: skin.accentSecondary,
                skin: skin,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatPace(double secPerKm) {
    final m = secPerKm ~/ 60;
    final s = (secPerKm % 60).round();
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

// ── Sensor status row (BLE + GPS) — siempre visible ─────────────

class _SensorStatusRow extends StatelessWidget {
  final dynamic skin;
  final ActiveSessionState session;
  final VoidCallback onConnectBle;
  const _SensorStatusRow(
      {required this.skin, required this.session, required this.onConnectBle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          Expanded(child: _BleCard(skin: skin, session: session, onConnect: onConnectBle)),
          const SizedBox(width: 8),
          Expanded(child: _GpsCard(skin: skin, session: session)),
        ],
      ),
    );
  }
}

class _BleCard extends StatelessWidget {
  final dynamic skin;
  final ActiveSessionState session;
  final VoidCallback onConnect;
  const _BleCard(
      {required this.skin, required this.session, required this.onConnect});

  @override
  Widget build(BuildContext context) {
    final connected = session.bleConnected;
    final name      = session.bleDeviceName ?? 'Sensor FC';
    final hr        = session.currentHR;

    return GestureDetector(
      onTap: connected ? null : onConnect,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: connected
              ? skin.success.withValues(alpha: 0.1)
              : skin.backgroundCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: connected ? skin.success : skin.border,
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            Icon(
              connected
                  ? Icons.bluetooth_connected
                  : Icons.bluetooth_searching,
              size: 18,
              color: connected ? skin.success : skin.textMuted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    connected ? name : 'Sin sensor FC',
                    style: TextStyle(
                      color: connected ? skin.success : skin.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (connected)
                    Text(
                      hr != null ? '$hr bpm' : 'Ponte la banda en el pecho',
                      style: TextStyle(
                        color: hr != null ? skin.error : skin.textMuted,
                        fontSize: hr != null ? 13 : 10,
                        fontWeight: hr != null ? FontWeight.w700 : FontWeight.normal,
                        fontFamily: hr != null ? skin.fontFamilyMono : null,
                      ),
                    )
                  else
                    Text(
                      'Toca para conectar',
                      style: TextStyle(color: skin.accent, fontSize: 11),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GpsCard extends StatelessWidget {
  final dynamic skin;
  final ActiveSessionState session;
  const _GpsCard({required this.skin, required this.session});

  @override
  Widget build(BuildContext context) {
    final active = session.gpsActive;
    final dist   = session.totalDistanceM;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: active ? skin.accent.withValues(alpha: 0.08) : skin.backgroundCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: active ? skin.accent : skin.border,
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Icon(
            active ? Icons.gps_fixed : Icons.gps_off,
            size: 18,
            color: active ? skin.accent : skin.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GPS',
                  style: TextStyle(
                    color: active ? skin.accent : skin.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  active
                      ? (dist > 0
                          ? '${(dist / 1000).toStringAsFixed(2)} km'
                          : 'Activo')
                      : 'Al comenzar',
                  style: TextStyle(
                    color: active ? skin.accentSecondary : skin.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFamily: dist > 0 ? skin.fontFamilyMono : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bloques del plan ────────────────────────────────────────────

class _SessionBlocks extends StatelessWidget {
  final List<dynamic> planned;
  final int elapsed;
  final dynamic skin;
  const _SessionBlocks(
      {required this.planned, required this.elapsed, required this.skin});

  static num _blockDurMin(Map<String, dynamic> b) {
    final v = b['min'] ?? b['durationMin'] ?? b['duracion_min'] ?? b['duration_min'] ?? b['dur_min'] ?? 0;
    if (v is num) return v;
    return num.tryParse(v.toString()) ?? 0;
  }

  int _activeIndex() {
    int cumSecs = 0;
    for (int i = 0; i < planned.length; i++) {
      final block  = planned[i] as Map<String, dynamic>? ?? {};
      final durMin = _blockDurMin(block);
      cumSecs += (durMin.toDouble() * 60).round();
      if (elapsed < cumSecs) return i;
    }
    return planned.isEmpty ? -1 : planned.length - 1;
  }

  @override
  Widget build(BuildContext context) {
    if (planned.isEmpty) {
      return Center(
        child: Text(
          'No hay bloques definidos para esta sesión.',
          style: TextStyle(color: skin.textMuted, fontSize: 13),
          textAlign: TextAlign.center,
        ),
      );
    }

    final activeIdx = _activeIndex();

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: planned.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _BlockCard(
        block: planned[i] as Map<String, dynamic>? ?? {},
        isActive: i == activeIdx,
        skin: skin,
        index: i,
      ),
    );
  }
}

class _BlockCard extends StatelessWidget {
  final Map<String, dynamic> block;
  final bool isActive;
  final dynamic skin;
  final int index;
  const _BlockCard(
      {required this.block,
      required this.isActive,
      required this.skin,
      required this.index});

  String _blockLabel() {
    final tipo = (block['block'] ?? block['blockType'] ?? block['tipo'] ?? block['type'] ?? block['nombre'] ?? '').toString();
    if (tipo.isEmpty) return 'Bloque ${index + 1}';
    return tipo[0].toUpperCase() + tipo.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final durMin = _SessionBlocks._blockDurMin(block);
    final zonaFC = block['zone'] ?? block['zona_fc'] ?? block['hr_zone'] ?? block['zona'];
    final ritmo  = block['ritmo_objetivo'] ?? block['target_pace'] ?? block['pace'];
    final desc   = block['descripcion'] ?? block['description'] ?? block['desc'] ?? '';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: isActive ? skin.accent.withValues(alpha: 0.12) : skin.backgroundCard,
        borderRadius: BorderRadius.circular(skin.cardRadius),
        border: Border.all(
          color: isActive ? skin.accent : skin.border,
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // Indicador bloque activo
            Container(
              width: 4,
              height: 48,
              decoration: BoxDecoration(
                color: isActive ? skin.accent : skin.border,
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
                      Text(
                        _blockLabel(),
                        style: TextStyle(
                          color: isActive ? skin.accent : skin.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${durMin.toInt()} min',
                        style: TextStyle(
                          fontFamily: skin.fontFamilyMono,
                          color: skin.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      desc.toString(),
                      style: TextStyle(
                          color: skin.textSecondary, fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (zonaFC != null || ritmo != null) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (zonaFC != null)
                          _Tag(
                              label: 'Z$zonaFC FC',
                              color: skin.error,
                              skin: skin),
                        if (ritmo != null)
                          _Tag(
                              label: ritmo.toString(),
                              color: skin.accent,
                              skin: skin),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color color;
  final dynamic skin;
  const _Tag({required this.label, required this.color, required this.skin});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label,
            style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5)),
      );
}

// ── Banner resumen cuando la sesión está completada ──────────────

class _CompletedSummaryBanner extends StatelessWidget {
  final dynamic skin;
  final Map<String, dynamic> sessionData;
  const _CompletedSummaryBanner({required this.skin, required this.sessionData});

  @override
  Widget build(BuildContext context) {
    final actualMin  = (sessionData['actual_duration_min'] as num?)?.toInt();
    final actualDistM= (sessionData['actual_distance_m']   as num?)?.toDouble();
    final actualHr   = (sessionData['actual_hr_avg_bpm']   as num?)?.toInt();
    final completedAt= sessionData['completed_at'] as String?;

    String? completedLabel;
    if (completedAt != null) {
      try {
        final dt = DateTime.parse(completedAt).toLocal();
        completedLabel = '${dt.day.toString().padLeft(2,'0')}/${dt.month.toString().padLeft(2,'0')} '
            '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
      } catch (_) {}
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: skin.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(skin.cardRadius),
        border: Border.all(color: skin.success.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.check_circle, color: skin.success, size: 16),
            const SizedBox(width: 8),
            Text('Sesión completada${completedLabel != null ? " · $completedLabel" : ""}',
                style: TextStyle(color: skin.success, fontWeight: FontWeight.w700, fontSize: 13)),
          ]),
          if (actualMin != null || actualDistM != null || actualHr != null) ...[
            const SizedBox(height: 10),
            Row(children: [
              if (actualMin != null)
                _SummaryChip(label: '${actualMin} min', icon: Icons.timer_outlined, skin: skin),
              if (actualDistM != null && actualDistM > 0)
                _SummaryChip(
                    label: '${(actualDistM / 1000).toStringAsFixed(2)} km',
                    icon: Icons.route_outlined, skin: skin),
              if (actualHr != null)
                _SummaryChip(label: '$actualHr bpm', icon: Icons.favorite_outline, skin: skin),
            ]),
          ],
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final dynamic skin;
  const _SummaryChip({required this.label, required this.icon, required this.skin});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 16),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: skin.textMuted),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(color: skin.textSecondary, fontSize: 12,
          fontFamily: skin.fontFamilyMono)),
    ]),
  );
}

// ── Pie de página cuando la sesión está completada ───────────────

class _CompletedFooter extends StatelessWidget {
  final dynamic skin;
  final VoidCallback onRedo;
  const _CompletedFooter({required this.skin, required this.onRedo});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      // Indicador visual "Completada"
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: skin.success.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(skin.cardRadius),
          border: Border.all(color: skin.success.withValues(alpha: 0.3)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.check_circle, color: skin.success, size: 20),
          const SizedBox(width: 10),
          Text('Completada — buen trabajo',
              style: TextStyle(color: skin.success, fontWeight: FontWeight.w600, fontSize: 14)),
        ]),
      ),
      const SizedBox(height: 10),
      // Botón "realizar de nuevo" discreto
      SizedBox(
        width: double.infinity,
        height: 44,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: skin.textMuted,
            side: BorderSide(color: skin.border),
          ),
          icon: Icon(Icons.replay, size: 16, color: skin.textMuted),
          label: Text('Realizar de nuevo',
              style: TextStyle(color: skin.textMuted, letterSpacing: 0.5)),
          onPressed: onRedo,
        ),
      ),
    ]),
  );
}

class _DataBadge extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final Color color;
  final SkinConfig skin;
  const _DataBadge(
      {required this.label,
      required this.value,
      required this.unit,
      required this.icon,
      required this.color,
      required this.skin});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(height: 4),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: value,
                style: TextStyle(
                  fontFamily: skin.fontFamilyMono,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              TextSpan(
                text: unit,
                style: TextStyle(
                  fontSize: 11,
                  color: skin.textMuted,
                ),
              ),
            ],
          ),
        ),
        Text(label,
            style: TextStyle(
                color: skin.textMuted, fontSize: 10, letterSpacing: 1.5)),
      ],
    );
  }
}
