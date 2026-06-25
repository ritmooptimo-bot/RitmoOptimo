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

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      ref.read(activeSessionProvider.notifier).tickSecond();
    });
  }

  Future<void> _onStart() async {
    final notifier = ref.read(activeSessionProvider.notifier);
    final ble      = ref.read(bleServiceProvider);
    final gps      = ref.read(gpsServiceProvider);

    // 1. BLE — si no hay sensor conectado, abrir scanner
    if (!ble.isConnected) {
      final device = await context.push<BluetoothDevice?>(
        '/ble-scan/${widget.sessionId}',
      );
      if (device != null) {
        await notifier.connectBLE(device);
      }
    }

    // 2. GPS — pedir permiso y empezar track
    final gpsOk = await gps.requestPermission();
    if (gpsOk) notifier.startGPS();

    // 3. Iniciar sesión en el backend
    await notifier.startSession(widget.sessionId);

    // 4. Arrancar timer
    _startTimer();
  }

  Future<void> _onFinish() async {
    _timer?.cancel();

    final notifier = ref.read(activeSessionProvider.notifier);
    final api      = ref.read(apiClientProvider);
    final session  = ref.read(activeSessionProvider);

    // 1. Parar GPS y recoger track
    final track = notifier.stopGPS();

    // 2. Subir track al backend (fire-and-forget)
    if (track.points.isNotEmpty) {
      api.postGPSTrack(widget.sessionId, track.toBackendPayload())
          .catchError((e) => debugPrint('[GPS] Error upload: $e'));
    }

    // 3. Desconectar BLE
    if (session.bleConnected) await notifier.disconnectBLE();

    if (mounted) {
      context.pushReplacement('/session/${widget.sessionId}/complete');
    }
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

    return Scaffold(
      backgroundColor: skin.background,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: skin.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          session.isRunning ? 'EN CURSO' : 'SESIÓN',
          style: TextStyle(
              color: skin.textPrimary, letterSpacing: 2, fontSize: 14),
        ),
        backgroundColor: skin.backgroundSecondary,
        actions: [
          if (session.isRunning)
            TextButton(
              onPressed: _onFinish,
              child: Text(
                'FINALIZAR',
                style: TextStyle(
                    color: skin.error,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Header: timer + FC + ritmo ───────────────────
          _SessionHeader(
            skin: skin,
            session: session,
            elapsed: _formatTime(session.elapsedSeconds),
          ),

          // ── BLE status chip ──────────────────────────────
          if (session.isRunning)
            _BleStatusChip(skin: skin, session: session),

          const SizedBox(height: 8),

          // ── Bloques del plan ─────────────────────────────
          Expanded(
            child: _SessionBlocks(
              planned: session.session?['planned_structure'] as List<dynamic>? ?? [],
              elapsed: session.elapsedSeconds,
              skin: skin,
            ),
          ),

          // ── Botón principal ──────────────────────────────
          Padding(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: session.isRunning
                  ? ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: skin.error,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _onFinish,
                      child: const Text(
                        'FINALIZAR SESIÓN',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, letterSpacing: 2),
                      ),
                    )
                  : ElevatedButton(
                      onPressed: _onStart,
                      child: const Text(
                        'COMENZAR',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, letterSpacing: 2),
                      ),
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
  const _SessionHeader(
      {required this.skin, required this.session, required this.elapsed});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      color: skin.backgroundSecondary,
      child: Column(
        children: [
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

// ── BLE status chip ──────────────────────────────────────────────

class _BleStatusChip extends StatelessWidget {
  final dynamic skin;
  final ActiveSessionState session;
  const _BleStatusChip({required this.skin, required this.session});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          Icon(
            session.bleConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
            size: 14,
            color: session.bleConnected ? skin.success : skin.textMuted,
          ),
          const SizedBox(width: 6),
          Text(
            session.bleConnected
                ? (session.bleDeviceName ?? 'Sensor conectado')
                : 'Sin sensor de FC',
            style: TextStyle(
                color: session.bleConnected ? skin.success : skin.textMuted,
                fontSize: 12),
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

  int _activeIndex() {
    int cumSecs = 0;
    for (int i = 0; i < planned.length; i++) {
      final block   = planned[i] as Map<String, dynamic>? ?? {};
      final durMin  = (block['duracion_min'] ?? block['duration_min'] ?? block['dur_min'] ?? 0) as num;
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
    final tipo = (block['tipo'] ?? block['type'] ?? block['nombre'] ?? '').toString();
    if (tipo.isEmpty) return 'Bloque ${index + 1}';
    // Capitalizar primera letra
    return tipo[0].toUpperCase() + tipo.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final durMin   = (block['duracion_min'] ?? block['duration_min'] ?? block['dur_min'] ?? 0) as num;
    final zonaFC   = block['zona_fc'] ?? block['hr_zone'] ?? block['zona'];
    final ritmo    = block['ritmo_objetivo'] ?? block['target_pace'] ?? block['pace'];
    final desc     = block['descripcion'] ?? block['description'] ?? block['desc'] ?? '';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: isActive ? skin.accent.withOpacity(0.12) : skin.backgroundCard,
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
          color: color.withOpacity(0.15),
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
