import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/skin_provider.dart';
import '../../providers/auth_provider.dart';

// ── Profile Screen ───────────────────────────────────────────────
// Perfil del atleta + selector de skin + configuración.

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin     = ref.watch(activeSkinProvider);
    final skinState = ref.watch(skinProvider);

    return Scaffold(
      backgroundColor: skin.background,
      appBar: AppBar(
        backgroundColor: skin.backgroundSecondary,
        title: Text('PERFIL',
            style: TextStyle(color: skin.textPrimary, letterSpacing: 2, fontSize: 14)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── Skin selector ────────────────────────────────
          Text('DISEÑO DE LA APP', style: TextStyle(
              color: skin.textMuted, fontSize: 10, letterSpacing: 2)),
          const SizedBox(height: 12),

          _SkinOption(
            title: 'Modo Oscuro',
            subtitle: 'Azul eléctrico · Diseño profesional',
            skinId: 'dark',
            isSelected: skinState.skin.name == 'Dark Mode',
            skin: skin,
            onTap: () => ref.read(skinProvider.notifier).setSkin('dark'),
          ),
          _SkinOption(
            title: 'Modo Día',
            subtitle: 'Azul profesional · Uso al aire libre',
            skinId: 'light',
            isSelected: skinState.skin.name == 'Light Mode',
            skin: skin,
            onTap: () => ref.read(skinProvider.notifier).setSkin('light'),
          ),
          _SkinOption(
            title: 'F1 Cockpit',
            subtitle: 'Rojo Ferrari · Telemetría · Datos en monospace',
            skinId: 'f1',
            isSelected: skinState.skin.name == 'F1 Cockpit',
            skin: skin,
            onTap: () => ref.read(skinProvider.notifier).setSkin('f1'),
          ),

          const SizedBox(height: 32),

          // ── Logout ───────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: skin.error,
                side: BorderSide(color: skin.error.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(skin.cardRadius),
                ),
              ),
              onPressed: () => ref.read(authProvider.notifier).logout(),
              child: const Text('Cerrar sesión',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

class _SkinOption extends StatelessWidget {
  final String title;
  final String subtitle;
  final String skinId;
  final bool isSelected;
  final dynamic skin;
  final VoidCallback onTap;

  const _SkinOption({
    required this.title, required this.subtitle, required this.skinId,
    required this.isSelected, required this.skin, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? skin.accent.withValues(alpha: 0.1)
              : skin.backgroundCard,
          borderRadius: BorderRadius.circular(skin.cardRadius),
          border: Border.all(
            color: isSelected ? skin.accent : skin.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: skin.textPrimary,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          color: skin.textMuted, fontSize: 12)),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: skin.accent, size: 22)
            else
              Icon(Icons.radio_button_unchecked,
                  color: skin.textMuted, size: 22),
          ],
        ),
      ),
    );
  }
}
