import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/skin_provider.dart';
import '../../providers/auth_provider.dart';
import '../../config/skins/skin_config.dart';
import '../../config/router.dart';
import 'garmin_screen.dart';

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
        // "Ajustes", no "Perfil": aquí no hay ni un dato personal —ni nombre, ni
        // correo, ni marcas—, solo el color de la app y el cierre de sesión.
        // Llamarlo perfil prometía una ficha de deportista que no existe.
        title: Text('Ajustes',
            style: TextStyle(color: skin.textPrimary, fontSize: 16,
                fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── Su reloj ─────────────────────────────────────
          //
          // Va lo primero a propósito: es lo único de esta pantalla que
          // cambia cómo entrena. El color de la app puede esperar.
          Text('Tu reloj', style: TextStyle(
              color: skin.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          _TarjetaGarmin(skin: skin),

          const SizedBox(height: 28),

          // ── Skin selector ────────────────────────────────
          Text('Diseño de la app', style: TextStyle(
              color: skin.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),

          // ⚠️ ESTA LISTA SE CONSTRUYE SOLA. NO AÑADAS PIELES A MANO AQUÍ.
          //
          // Antes había un bloque escrito a mano por piel, con su título y su
          // descripción metidos en esta pantalla. Eso obligaba a entrar aquí cada
          // vez que se creaba una piel nueva — y las pieles las hace otra sesión,
          // que no tiene por qué tocar pantallas.
          //
          // Ahora una piel nueva es SOLO su fichero en `config/skins/` más su
          // línea en `availableSkins`. El nombre visible y la descripción viajan
          // dentro de la propia piel (`etiqueta` y `descripcion`), que es su
          // sitio: quien elige los colores elige cómo se llaman.
          //
          // El orden es el del mapa: Dart conserva el de inserción.
          ...availableSkins.entries.map((entrada) => _SkinOption(
                title: entrada.value.etiqueta.isNotEmpty
                    ? entrada.value.etiqueta
                    : entrada.value.name,
                subtitle: entrada.value.descripcion,
                // `name` es único e interno; comparar por él evita depender de
                // que el estado guarde también la clave del mapa.
                isSelected: skinState.skin.name == entrada.value.name,
                skin: skin,
                onTap: () =>
                    ref.read(skinProvider.notifier).setSkin(entrada.key),
              )),

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

// ── LA TARJETA DEL RELOJ ─────────────────────────────────────────────
//
// Enseña el estado sin tener que entrar: conectado y con cuántas noches, o
// la invitación a conectarlo. Un simple "Reloj Garmin >" obligaría a entrar
// solo para ver si sigue funcionando.
class _TarjetaGarmin extends ConsumerWidget {
  final SkinConfig skin;
  const _TarjetaGarmin({required this.skin});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(garminEstadoProvider);

    // Mientras carga o si falla NO se dice "sin conectar": sería mentir con
    // cara de dato. Se deja el titular y ya.
    final e = estado.valueOrNull;
    final vinculado = e?['vinculado'] == true;
    final noches = (e?['noches'] as num?)?.toInt() ?? 0;
    final corta = e?['historiaCorta'] == true;

    final String detalle;
    if (e == null) {
      detalle = 'Sueño, HRV y pulso en reposo, medidos toda la noche';
    } else if (!vinculado) {
      detalle = 'Conéctalo y el plan se ajusta a cómo descansas de verdad';
    } else if (corta) {
      detalle = 'Conectado · te falta tu historia';
    } else {
      detalle = 'Conectado · $noches ${noches == 1 ? 'noche' : 'noches'}';
    }

    final color = e == null
        ? skin.textMuted
        : (!vinculado ? skin.accent : (corta ? skin.warning : skin.success));

    return GestureDetector(
      onTap: () => context.push(AppRoutes.garmin),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: skin.backgroundCard,
          borderRadius: BorderRadius.circular(skin.cardRadius),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(
          children: [
            Icon(Icons.watch_outlined, color: color, size: 24),
            const SizedBox(width: 14),
            // ⚠️ Expanded: con la letra al 180 % un texto que no puede
            // encoger se recorta sin avisar de nada.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Reloj Garmin',
                      style: TextStyle(color: skin.textPrimary,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(detalle,
                      style: TextStyle(color: skin.textMuted, fontSize: 12,
                          height: 1.35)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: skin.textMuted, size: 22),
          ],
        ),
      ),
    );
  }
}

class _SkinOption extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isSelected;
  final SkinConfig skin;
  final VoidCallback onTap;

  // `skinId` estaba declarado y era obligatorio, pero no se usaba en ninguna
  // parte del widget: se pasaba tres veces para nada. Fuera.
  const _SkinOption({
    required this.title, required this.subtitle,
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
                  // Sin descripción no se pinta la línea. Una piel de fuera que
                  // no la rellene deja un hueco en blanco dentro de la tarjeta,
                  // y parece que falta algo en vez de que sobre.
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(
                            color: skin.textMuted, fontSize: 12)),
                  ],
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
