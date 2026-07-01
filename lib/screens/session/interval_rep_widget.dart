import 'package:flutter/material.dart';
import '../../config/skins/skin_config.dart';

/// Widget de ritmo en tiempo real para intervalos.
/// Verde si diff ≤ ±5 s/km, amarillo ≤ ±15 s/km, rojo > 15 s/km.
class IntervalRepWidget extends StatelessWidget {
  final double smoothedPaceSecKm; // 0 = sin datos
  final String? targetPace;       // "4:30" o null
  final SkinConfig skin;

  const IntervalRepWidget({
    super.key,
    required this.smoothedPaceSecKm,
    required this.skin,
    this.targetPace,
  });

  @override
  Widget build(BuildContext context) {
    final hasPace = smoothedPaceSecKm > 0;

    if (!hasPace) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: skin.backgroundCard,
          borderRadius: BorderRadius.circular(skin.cardRadius),
          border: Border.all(color: skin.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.speed, size: 16, color: skin.textMuted),
            const SizedBox(width: 8),
            Text(
              'Esperando datos GPS…',
              style: TextStyle(color: skin.textMuted, fontSize: 12),
            ),
          ],
        ),
      );
    }

    final paceStr   = _fmtPace(smoothedPaceSecKm.round());
    final targetSec = targetPace != null ? _parsePace(targetPace!) : null;
    final diff      = targetSec != null ? (smoothedPaceSecKm - targetSec).round() : null;
    final color     = diff != null ? _diffColor(diff) : skin.accent;
    final arrow     = diff != null ? _arrow(diff)     : null;
    final label     = diff != null ? _label(diff)     : null;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(skin.cardRadius),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Row(
        children: [
          // Ritmo actual
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'RITMO ACTUAL',
                style: TextStyle(
                  color: skin.textMuted,
                  fontSize: 9,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                paceStr,
                style: TextStyle(
                  fontFamily: skin.fontFamilyMono,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              Text(
                'min/km',
                style: TextStyle(color: skin.textMuted, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(width: 16),
          // Flecha dirección
          if (arrow != null)
            Icon(arrow, color: color, size: 32),
          const Spacer(),
          // Objetivo + evaluación
          if (targetPace != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'OBJETIVO',
                  style: TextStyle(
                    color: skin.textMuted,
                    fontSize: 9,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  targetPace!,
                  style: TextStyle(
                    fontFamily: skin.fontFamilyMono,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: skin.textSecondary,
                  ),
                ),
                if (label != null)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Color _diffColor(int diff) {
    // diff > 0 → más lento que objetivo; diff < 0 → más rápido
    if (diff.abs() <= 5) return const Color(0xFF22C55E);  // verde
    if (diff.abs() <= 15) return const Color(0xFFEAB308); // amarillo
    return const Color(0xFFEF4444);                        // rojo
  }

  IconData? _arrow(int diff) {
    if (diff.abs() <= 5)  return Icons.check_circle_outline;
    if (diff < 0) return Icons.arrow_upward;  // más rápido (pace bajo)
    return Icons.arrow_downward;              // más lento (pace alto)
  }

  String _label(int diff) {
    if (diff.abs() <= 5)  return 'Perfecto';
    if (diff < -5)        return 'Algo rápido';
    if (diff <= 15)       return 'Ligeramente alto';
    return 'Por encima';
  }

  static String _fmtPace(int secKm) {
    final m = secKm ~/ 60;
    final s = (secKm % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  static int _parsePace(String pace) {
    final parts = pace.split(':');
    if (parts.length != 2) return 0;
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }
}
