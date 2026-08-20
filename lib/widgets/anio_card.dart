import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_client.dart';

// ── TU AÑO ───────────────────────────────────────────────────────────
//
// Teníamos 382 noches de su reloj guardadas y NI ÉL NI SU ENTRENADOR podían
// verlas. Las tarjetas de arriba miran ventanas cortas a propósito —la línea
// base son 7 días, la readiness es de hoy— porque para decidir el entrenamiento
// de mañana eso es lo que vale. Pero deja la historia invisible: este
// deportista venía de medio año hundido y no había dónde mirarlo.
//
// ⚠️ NO ES LA MISMA LECTURA QUE VE EL ENTRENADOR, y no es un capricho:
//
//   · Los NÚMEROS son los mismos (salen de `hechosDelAnio`, se calculan una
//     sola vez en el servidor). El día que le enseñe esta pantalla a su
//     entrenador tienen que estar hablando de lo mismo.
//   · La VOZ no. Al entrenador se le da la coincidencia con la carga porque
//     sabe qué hacer con ella; a él «ese mes entrenaste mucho» le invitaría a
//     bajarse el entrenamiento por su cuenta, que es la decisión de su
//     entrenador. Y cuando algo va mal, a él se le manda a hablarlo en vez de
//     dejarle una sentencia en una pantalla y nadie al lado.
//
// Todo eso vive en el SERVIDOR: aquí no se decide nada, solo se pinta.
class AnioCard extends ConsumerStatefulWidget {
  final dynamic skin;
  const AnioCard({super.key, required this.skin});
  @override
  ConsumerState<AnioCard> createState() => _AnioCardState();
}

class _AnioCardState extends ConsumerState<AnioCard> {
  Map<String, dynamic>? _a;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final a = await ref.read(apiClientProvider).getAnio();
      if (mounted) setState(() { _a = a; _cargando = false; });
    } catch (_) {
      // Sin año no se pinta nada. Una tarjeta con un error dentro, en una
      // pantalla que va de cómo estás, solo preocupa sin decir nada útil.
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    final a = _a;
    if (_cargando || a == null) return const SizedBox.shrink();

    final meses = (a['meses'] as List?) ?? const [];
    final lectura = (a['lectura'] as List?) ?? const [];
    // Sin reloj enlazado no hay año que contar: la tarjeta desaparece entera en
    // vez de dejar un hueco que parece roto.
    if (meses.length < 3 || lectura.isEmpty) return const SizedBox.shrink();

    final noches = (a['noches'] as num?)?.toInt() ?? 0;
    final serie = meses
        .map((m) => (m as Map)['hrv'])
        .whereType<num>()
        .map((x) => x.toDouble())
        .toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.calendar_month, color: skin.accent, size: 22),
                const SizedBox(width: 10),
                // ⚠️ Expanded: con la letra al 180 % un texto que no puede
                // encoger se recorta sin avisar de nada.
                Expanded(
                  child: Text('Tu año',
                      style: TextStyle(color: skin.textPrimary, fontSize: 15,
                          fontWeight: FontWeight.w700)),
                ),
                Flexible(
                  child: Text('$noches noches',
                      textAlign: TextAlign.end,
                      style: TextStyle(color: skin.textMuted, fontSize: 11)),
                ),
              ],
            ),

            if (serie.length >= 3) ...[
              const SizedBox(height: 12),
              SizedBox(height: 58, child: _sparkline(skin, serie)),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(_primerMes(meses),
                        style: TextStyle(color: skin.textMuted, fontSize: 10)),
                  ),
                  Text('hoy',
                      style: TextStyle(color: skin.textMuted, fontSize: 10)),
                ],
              ),
            ],

            const SizedBox(height: 12),
            ...lectura.map((l) => _linea(skin, l as Map)),
          ],
        ),
      ),
    );
  }

  /// El HRV de los últimos trece meses, sin ejes ni números: lo que se quiere
  /// ver de un vistazo es la FORMA. Los números van en las frases de abajo.
  Widget _sparkline(dynamic skin, List<double> serie) {
    final bajo = serie.reduce((a, b) => a < b ? a : b);
    final alto = serie.reduce((a, b) => a > b ? a : b);
    // ⚠️ Un recorrido mínimo, o cualquier vaivén parece un desplome. En el panel
    // pasó igual: con la FC entre 54 y 58, cuatro pulsaciones llenaban el
    // gráfico entero y el de al lado, con veinte de diferencia, se veía igual.
    final centro = (bajo + alto) / 2;
    final medio = (alto - bajo < 15 ? 15.0 : alto - bajo) / 2 * 1.15;

    return LineChart(
      LineChartData(
        minY: centro - medio,
        maxY: centro + medio,
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < serie.length; i++) FlSpot(i.toDouble(), serie[i]),
            ],
            isCurved: true,
            curveSmoothness: 0.3,
            preventCurveOverShooting: true,
            barWidth: 2,
            color: skin.accent,
            belowBarData: BarAreaData(
              show: true, color: skin.accent.withValues(alpha: 0.12)),
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, pct, bar, index) => FlDotCirclePainter(
                // El último punto, más gordo: es dónde está hoy.
                radius: index == serie.length - 1 ? 3.4 : 1.6,
                color: skin.accent,
                strokeWidth: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _linea(dynamic skin, Map l) {
    final tono = l['tono'] as String? ?? 'info';
    final Color color = tono == 'bien'
        ? skin.success
        : (tono == 'ojo' ? skin.warning : skin.textMuted);
    final IconData icono = tono == 'bien'
        ? Icons.trending_up
        : (tono == 'ojo' ? Icons.info_outline : Icons.remove);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: color, size: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${l['texto']}',
                style: TextStyle(
                    color: skin.textSecondary, fontSize: 12.5, height: 1.35)),
          ),
        ],
      ),
    );
  }

  static const _mesesCortos = ['ene', 'feb', 'mar', 'abr', 'may', 'jun',
                         'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

  String _primerMes(List meses) {
    final m = (meses.first as Map)['mes'] as String? ?? '';
    final p = m.split('-');
    if (p.length != 2) return m;
    final i = int.tryParse(p[1]);
    if (i == null || i < 1 || i > 12) return m;
    return '${_mesesCortos[i - 1]} ${p[0].substring(2)}';
  }
}
