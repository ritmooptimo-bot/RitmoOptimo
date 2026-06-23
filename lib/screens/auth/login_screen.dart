import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../providers/skin_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  bool _loading    = false;
  bool _obscure    = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _showActivationDialog(BuildContext context, dynamic skin) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: skin.backgroundCard,
        title: Text('Código de activación', style: TextStyle(color: skin.textPrimary, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Pega aquí el enlace de activación que te envió tu entrenador:',
              style: TextStyle(color: skin.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              style: TextStyle(color: skin.textPrimary, fontSize: 13),
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'https://ritmooptimo.tech/app/activar?token=...',
                hintStyle: TextStyle(color: skin.textMuted, fontSize: 11),
                filled: true,
                fillColor: skin.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancelar', style: TextStyle(color: skin.textMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              final raw = ctrl.text.trim();
              final token = _extractToken(raw);
              if (token.isEmpty) return;
              Navigator.of(context).pop();
              context.go('/pair?token=$token');
            },
            child: const Text('Activar'),
          ),
        ],
      ),
    );
  }

  String _extractToken(String input) {
    try {
      final uri = Uri.tryParse(input);
      if (uri != null) {
        final t = uri.queryParameters['token'];
        if (t != null && t.isNotEmpty) return t;
      }
    } catch (_) {}
    // Si es directamente el token (64 chars hex)
    if (RegExp(r'^[0-9a-f]{64}$').hasMatch(input)) return input;
    return '';
  }

  Future<void> _login() async {
    if (_emailCtrl.text.trim().isEmpty || _passCtrl.text.isEmpty) return;
    setState(() => _loading = true);
    await ref.read(authProvider.notifier).login(
      _emailCtrl.text.trim().toLowerCase(),
      _passCtrl.text,
    );
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final skin  = ref.watch(activeSkinProvider);
    final auth  = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: skin.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),

              // Logo / Brand
              Text(
                'RITMO',
                style: TextStyle(
                  fontFamily: skin.fontFamily,
                  fontSize: 40,
                  fontWeight: FontWeight.w700,
                  color: skin.accent,
                  letterSpacing: 4,
                ),
              ),
              Text(
                'ÓPTIMO',
                style: TextStyle(
                  fontFamily: skin.fontFamily,
                  fontSize: 40,
                  fontWeight: FontWeight.w300,
                  color: skin.textPrimary,
                  letterSpacing: 4,
                  height: 0.9,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Tu entrenador de IA',
                style: TextStyle(
                  color: skin.textMuted,
                  fontSize: 14,
                ),
              ),

              const Spacer(),

              // Error
              if (auth.error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: skin.error.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(skin.cardRadius),
                    border: Border.all(color: skin.error.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    auth.error!,
                    style: TextStyle(color: skin.error, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Email
              _Field(
                controller: _emailCtrl,
                hint: 'Email',
                keyboardType: TextInputType.emailAddress,
                skin: skin,
              ),
              const SizedBox(height: 12),

              // Password
              _Field(
                controller: _passCtrl,
                hint: 'Contraseña',
                obscure: _obscure,
                skin: skin,
                suffix: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility_off : Icons.visibility,
                    color: skin.textMuted,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              const SizedBox(height: 24),

              // Login button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _login,
                  child: _loading
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: skin.background,
                          ),
                        )
                      : const Text(
                          'ENTRAR',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 20),

              // Enlace de activación manual (fallback si el deep link no funciona)
              Center(
                child: TextButton(
                  onPressed: () => _showActivationDialog(context, skin),
                  child: Text(
                    '¿Primer acceso? Introduce tu código de activación',
                    style: TextStyle(color: skin.textMuted, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final Widget? suffix;
  final dynamic skin;

  const _Field({
    required this.controller,
    required this.hint,
    required this.skin,
    this.obscure = false,
    this.keyboardType,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: TextStyle(color: skin.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: skin.textMuted),
        suffixIcon: suffix,
        filled: true,
        fillColor: skin.backgroundCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(skin.cardRadius),
          borderSide: BorderSide(color: skin.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(skin.cardRadius),
          borderSide: BorderSide(color: skin.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(skin.cardRadius),
          borderSide: BorderSide(color: skin.accent, width: 2),
        ),
      ),
    );
  }
}
