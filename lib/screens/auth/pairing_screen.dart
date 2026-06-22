import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/app_auth_client.dart';
import '../../providers/auth_provider.dart';

// ── PairingScreen ─────────────────────────────────────────────────
// Se muestra cuando la app recibe el deep link ritmooptimo://pair?token=XXX
// Llama a POST /api/app/pair-device y actualiza el estado de auth.
class PairingScreen extends ConsumerStatefulWidget {
  final String token;
  const PairingScreen({super.key, required this.token});

  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen> {
  _Phase _phase = _Phase.pairing;
  String? _errorMsg;
  String? _athleteName;

  @override
  void initState() {
    super.initState();
    _runPairing();
  }

  Future<void> _runPairing() async {
    try {
      final client   = ref.read(appAuthClientProvider);
      final platform = Platform.isIOS ? 'ios' : 'android';

      final result = await client.pairDevice(
        pairingToken: widget.token,
        platform: platform,
        deviceName: _buildDeviceName(),
      );

      // Notificar al authProvider que hay sesión válida
      await ref.read(authProvider.notifier).onDevicePaired();

      setState(() {
        _phase       = _Phase.success;
        _athleteName = result['athlete']?['nombre'] as String?;
      });

    } on Exception catch (e) {
      final msg = e.toString();
      setState(() {
        _phase    = _Phase.error;
        _errorMsg = _friendlyError(msg);
      });
    }
  }

  String _buildDeviceName() {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS)     return 'iPhone';
    return 'Mobile';
  }

  String _friendlyError(String raw) {
    if (raw.contains('ya fue utilizado'))   return 'Este código QR ya fue usado.\nPide a tu entrenador un nuevo acceso.';
    if (raw.contains('caducado'))           return 'El código QR ha caducado (48h).\nPide a tu entrenador un nuevo acceso.';
    if (raw.contains('Ya tienes un dispositivo')) return 'Ya tienes un dispositivo vinculado.\nContacta con soporte para cambiarlo.';
    return 'No se pudo vincular el dispositivo.\nComprueba tu conexión e inténtalo de nuevo.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: switch (_phase) {
              _Phase.pairing => _PairingView(),
              _Phase.success => _SuccessView(name: _athleteName, onContinue: _goHome),
              _Phase.error   => _ErrorView(message: _errorMsg!, onRetry: _goBack),
            },
          ),
        ),
      ),
    );
  }

  void _goHome() => context.go('/');
  void _goBack() => context.go('/login');
}

// ── Subvistas ─────────────────────────────────────────────────────

class _PairingView extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const _Logo(),
      const SizedBox(height: 40),
      const SizedBox(
        width: 56, height: 56,
        child: CircularProgressIndicator(
          color: Color(0xFFE6813B), strokeWidth: 3,
        ),
      ),
      const SizedBox(height: 28),
      Text(
        'Vinculando dispositivo...',
        style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 10),
      Text(
        'Estamos configurando tu acceso exclusivo.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFF94A3B8)),
        textAlign: TextAlign.center,
      ),
    ],
  );
}

class _SuccessView extends StatelessWidget {
  final String? name;
  final VoidCallback onContinue;
  const _SuccessView({this.name, required this.onContinue});

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const _Logo(),
      const SizedBox(height: 36),
      const Text('🎉', style: TextStyle(fontSize: 64)),
      const SizedBox(height: 20),
      Text(
        name != null ? '¡Hola, $name!' : '¡Dispositivo vinculado!',
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          color: Colors.white, fontWeight: FontWeight.w700,
        ),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 10),
      Text(
        'Tu acceso exclusivo está listo.\nEste dispositivo queda vinculado a tu cuenta.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFF94A3B8)),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 36),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: onContinue,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFE6813B),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Comenzar →', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      ),
    ],
  );
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const _Logo(),
      const SizedBox(height: 36),
      const Text('⚠️', style: TextStyle(fontSize: 56)),
      const SizedBox(height: 20),
      Text(
        'No se pudo activar',
        style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF87171).withOpacity(0.12),
          border: Border.all(color: const Color(0xFFF87171).withOpacity(0.35)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          message,
          style: const TextStyle(color: Color(0xFFF87171), fontSize: 14, height: 1.55),
          textAlign: TextAlign.center,
        ),
      ),
      const SizedBox(height: 28),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: onRetry,
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFE6813B),
            side: const BorderSide(color: Color(0xFFE6813B)),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Ir al inicio de sesión', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ),
      ),
    ],
  );
}

class _Logo extends StatelessWidget {
  const _Logo();
  @override
  Widget build(BuildContext context) => RichText(
    text: const TextSpan(
      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5),
      children: [
        TextSpan(text: 'Ritmo', style: TextStyle(color: Color(0xFFE6813B))),
        TextSpan(text: 'Óptimo', style: TextStyle(color: Colors.white)),
      ],
    ),
  );
}

// ── Enum de fases ─────────────────────────────────────────────────
enum _Phase { pairing, success, error }
