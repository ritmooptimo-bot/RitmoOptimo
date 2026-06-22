import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/skin_provider.dart';
import '../../providers/workout_provider.dart';
import '../../config/skins/skin_config.dart';

// ── Session Screen ───────────────────────────────────────────────
// Pantalla de sesión activa: timer, FC en tiempo real, bloques.
// Llama a POST /sessions/:id/start al pulsar "Comenzar".
// Al finalizar navega a SessionCompleteScreen para guardar datos reales.

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
    await ref.read(activeSessionProvider.notifier).startSession(widget.sessionId);
    _startTimer();
  }

  String _formatTime(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '${h.toString().padLeft(2,'0')}:${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}';
    return '${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}';
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
          style: TextStyle(color: skin.textPrimary, letterSpacing: 2, fontSize: 14),
        ),
        backgroundColor: skin.backgroundSecondary,
        actions: [
          if (session.isRunning)
            TextButton(
              onPressed: () => context.pushReplacement(
                '/session/${widget.sessionId}/complete',
              ),
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
          // ── Timer / HR display ──────────────────────────
          _SessionHeader(
            skin: skin,
            session: session,
            elapsed: _formatTime(session.elapsedSeconds),
          ),

          const SizedBox(height: 16),

          // ── Bloques (estructura del plan) ───────────────
          Expanded(
            child: Center(
              child: Text(
                'Bloques de la sesión\n(Phase 2)',
                textAlign: TextAlign.center,
                style: TextStyle(color: skin.textMuted),
              ),
            ),
          ),

          // ── Botón principal ─────────────────────────────
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
                      onPressed: () => context.pushReplacement(
                        '/session/${widget.sessionId}/complete',
                      ),
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      color: skin.backgroundSecondary,
      child: Column(
        children: [
          // Timer
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
          // HR + Pace
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
                value: session.currentPace != null
                    ? _formatPace(session.currentPace!)
                    : '--:--',
                unit: '/km',
                icon: Icons.speed,
                color: skin.accent,
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
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              TextSpan(
                text: unit,
                style: TextStyle(
                  fontSize: 12,
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
