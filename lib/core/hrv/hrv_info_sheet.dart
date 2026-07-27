import 'package:flutter/material.dart';
import '../../config/skins/skin_config.dart';
import 'hrv_references.dart';

// Hoja inferior "ⓘ" que explica FC y HRV CON LOS DATOS DEL DEPORTISTA (su FC,
// su HRV, su edad) — para que entienda qué son y qué es lo óptimo para él, no
// una explicación genérica. Compartida por la medición con banda y con cámara.
Future<void> showHrvInfoSheet(
  BuildContext context,
  SkinConfig skin, {
  required int fc,
  int? hrv,
  int? age,
  bool cameraHrv = false,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: skin.backgroundSecondary,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      builder: (_, controller) => SingleChildScrollView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: skin.textMuted.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text('Qué significan tus números',
                style: TextStyle(
                    color: skin.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 18),
            _section(skin, Icons.favorite, 'FC en reposo', skin.error,
                fcInfoText(fc)),
            const SizedBox(height: 18),
            _section(skin, Icons.monitor_heart_outlined, 'HRV (variabilidad)',
                skin.accent, hrvInfoText(hrv, age, cameraEstimate: cameraHrv)),
          ],
        ),
      ),
    ),
  );
}

Widget _section(
    SkinConfig skin, IconData icon, String title, Color color, String body) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 8),
        Text(title,
            style: TextStyle(
                color: color, fontSize: 15, fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 8),
      Text(body,
          style: TextStyle(
              color: skin.textSecondary, fontSize: 13.5, height: 1.4)),
    ],
  );
}
