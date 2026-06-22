import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

              const SizedBox(height: 32),
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
