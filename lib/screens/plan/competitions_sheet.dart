import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/skin_provider.dart';
import '../../core/network/api_client.dart';

// ── MIS COMPETICIONES ─────────────────────────────────────────────────
//
// El deportista apunta aquí su competición y el plan se reorganiza para que
// llegue en su mejor versión. Hasta ahora solo el entrenador podía darlas de
// alta, así que el caso más real —"me he apuntado y es dentro de dos semanas"—
// no tenía salida.
//
// Se dice COMPETICIÓN y no "carrera" a propósito: la app es multideporte
// (running, trail, ciclismo, natación, triatlón y fuerza) y un ciclista o un
// nadador que lee "carreras" duda de si la función va con él.
//
// NUNCA se le piden roles técnicos (primario, secundario A/B): ese es el idioma
// del entrenador. A él solo se le pregunta si va a por ella o la corre de
// preparación, y el sistema deduce el resto con la metodología del entrenador.

final competicionesProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  try {
    return await ref.read(apiClientProvider).getCompetitions();
  } catch (_) {
    return null;
  }
});

String fechaLarga(String iso) {
  try {
    const m = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio',
               'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
    final d = DateTime.parse(iso);
    return '${d.day} de ${m[d.month - 1]} de ${d.year}';
  } catch (_) {
    return iso;
  }
}

/// Fila visible en el Plan: la puerta principal a las carreras.
///
/// Un icono suelto en una esquina no lo descubre nadie para algo que se hace
/// tres veces al año. Esto se ve sin buscar y cambia según su situación: si no
/// tiene ninguna, le invita; si tiene, le dice cuál es la próxima y cuánto falta.
class AvisoCarreras extends ConsumerWidget {
  final VoidCallback onTap;
  const AvisoCarreras({super.key, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin = ref.watch(activeSkinProvider);
    final d = ref.watch(competicionesProvider).valueOrNull;
    if (d == null) return const SizedBox.shrink();

    final lista = (d['competitions'] as List?) ?? [];
    String titulo, sub;
    IconData icono;
    Color color;

    if (lista.isEmpty) {
      icono = Icons.flag_outlined;
      color = skin.textMuted;
      titulo = '¿Tienes alguna competición a la vista?';
      sub = 'Apúntala y organizo tu plan para que llegues en tu mejor versión.';
    } else {
      final prox = lista.first as Map<String, dynamic>;
      int? dias;
      try {
        dias = DateTime.parse(prox['fecha'] as String)
            .difference(DateTime.now()).inDays + 1;
      } catch (_) {}
      final esPrincipal = prox['role'] == 'primario';
      icono = Icons.flag;
      color = esPrincipal ? skin.accent : skin.textSecondary;
      titulo = prox['name']?.toString() ?? 'Tu próxima competición';
      sub = [
        if (dias != null && dias > 0) 'En $dias días',
        if (esPrincipal) 'Tu objetivo principal',
      ].join(' · ');
      if (sub.isEmpty) sub = 'Toca para ver el detalle';
    }

    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: skin.backgroundSecondary,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(icono, color: color, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo,
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: skin.textPrimary,
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(sub,
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: skin.textMuted, fontSize: 12.5, height: 1.3)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: skin.textMuted, size: 20),
          ],
        ),
      ),
    );
  }
}

class CompetitionsSheet extends ConsumerWidget {
  const CompetitionsSheet({super.key});

  static const _rolTexto = {
    'primario': 'Tu objetivo principal',
    'secundario_a': 'Test de ritmo antes de tu objetivo',
    'secundario_b': 'Estímulo de resistencia',
    'popular': 'De preparación',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin = ref.watch(activeSkinProvider);
    final data = ref.watch(competicionesProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      expand: false,
      builder: (ctx, scroll) => Container(
        decoration: BoxDecoration(
          color: skin.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: skin.textMuted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Mis competiciones',
                        style: TextStyle(color: skin.textPrimary,
                            fontSize: 20, fontWeight: FontWeight.w700)),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Añadir'),
                    style: TextButton.styleFrom(foregroundColor: skin.accent),
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => _DialogoNuevaCarrera(
                        onGuardada: () => ref.invalidate(competicionesProvider),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: data.when(
                loading: () => Center(child: CircularProgressIndicator(color: skin.accent)),
                error: (_, __) => _vacio(skin, 'No se pudieron cargar tus competiciones.'),
                data: (d) {
                  final lista = (d?['competitions'] as List?) ?? [];
                  final fase = d?['fase'] as Map<String, dynamic>?;
                  if (lista.isEmpty) {
                    return _vacio(skin,
                        'Aún no tienes ninguna competición apuntada.\n\nCuando apuntes una, tu plan se reorganiza solo para que llegues en tu mejor versión.');
                  }
                  return ListView(
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                    children: [
                      if (fase?['texto'] != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: skin.accent.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(fase!['texto'] as String,
                              style: TextStyle(color: skin.textSecondary,
                                  fontSize: 13, height: 1.4)),
                        ),
                      ...lista.map((c) =>
                          _tarjeta(ref, skin, c as Map<String, dynamic>)),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vacio(dynamic skin, String texto) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.emoji_events_outlined, size: 44, color: skin.textMuted),
              const SizedBox(height: 14),
              Text(texto, textAlign: TextAlign.center,
                  style: TextStyle(color: skin.textSecondary, height: 1.45)),
            ],
          ),
        ),
      );

  Widget _tarjeta(WidgetRef ref, dynamic skin, Map<String, dynamic> c) {
    final rol = c['role'] as String? ?? 'popular';
    final esPrincipal = rol == 'primario';
    final fecha = c['fecha'] as String? ?? '';
    int? dias;
    try {
      dias = DateTime.parse(fecha).difference(DateTime.now()).inDays + 1;
    } catch (_) {}

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: skin.backgroundSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(
              color: esPrincipal ? skin.accent : skin.textMuted, width: 4),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c['name']?.toString() ?? 'Competición',
                    style: TextStyle(color: skin.textPrimary,
                        fontSize: 15.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(
                  [
                    fechaLarga(fecha),
                    if (c['distance'] != null) '${c['distance']} km',
                    if (dias != null && dias > 0) 'en $dias días',
                  ].join(' · '),
                  style: TextStyle(color: skin.textMuted, fontSize: 12.5),
                ),
                const SizedBox(height: 5),
                Text(_rolTexto[rol] ?? '',
                    style: TextStyle(
                        color: esPrincipal ? skin.accent : skin.textSecondary,
                        fontSize: 12.5, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 18, color: skin.textMuted),
            tooltip: 'Quitar',
            onPressed: () async {
              try {
                await ref.read(apiClientProvider).deleteCompetition(c['id'].toString());
                ref.invalidate(competicionesProvider);
              } catch (_) {}
            },
          ),
        ],
      ),
    );
  }
}

class _DialogoNuevaCarrera extends ConsumerStatefulWidget {
  final VoidCallback onGuardada;
  const _DialogoNuevaCarrera({required this.onGuardada});
  @override
  ConsumerState<_DialogoNuevaCarrera> createState() => _DialogoNuevaCarreraState();
}

class _DialogoNuevaCarreraState extends ConsumerState<_DialogoNuevaCarrera> {
  final _nombre = TextEditingController();
  final _distancia = TextEditingController();
  DateTime? _fecha;
  bool? _aPorElla;
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _nombre.dispose();
    _distancia.dispose();
    super.dispose();
  }

  Future<void> _guardar(BuildContext ctx) async {
    if (_nombre.text.trim().isEmpty || _fecha == null) {
      setState(() => _error = 'Necesito al menos el nombre y la fecha.');
      return;
    }
    // Teclado español: la coma decimal daba null en silencio y se perdía el dato.
    final txt = _distancia.text.trim().replaceAll(',', '.');
    final km = txt.isEmpty ? null : double.tryParse(txt);
    if (txt.isNotEmpty && km == null) {
      setState(() => _error = 'La distancia no se entiende. Ejemplo: 21,1');
      return;
    }

    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await ref.read(apiClientProvider).addCompetition(
            name: _nombre.text.trim(),
            date: _fecha!.toIso8601String().split('T')[0],
            distanceKm: km,
            vaAPorElla: _aPorElla,
          );
      widget.onGuardada();
      if (mounted) Navigator.of(ctx).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _guardando = false;
          _error = 'No se pudo guardar. Inténtalo de nuevo.';
        });
      }
    }
  }

  Widget _opcion(dynamic skin, bool valor, String texto) {
    final sel = _aPorElla == valor;
    return InkWell(
      onTap: () => setState(() => _aPorElla = valor),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: sel ? skin.accent.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: sel ? skin.accent : skin.textMuted.withValues(alpha: 0.4),
              width: sel ? 2 : 1),
        ),
        child: Row(
          children: [
            Icon(sel ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                size: 18, color: sel ? skin.accent : skin.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(texto,
                  style: TextStyle(
                      color: sel ? skin.textPrimary : skin.textSecondary,
                      fontSize: 13.5,
                      fontWeight: sel ? FontWeight.w600 : FontWeight.w400)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final skin = ref.watch(activeSkinProvider);
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: skin.backgroundSecondary,
      title: Text('Apuntar una competición',
          style: TextStyle(color: skin.textPrimary, fontWeight: FontWeight.w700)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nombre,
              style: TextStyle(color: skin.textPrimary),
              decoration: InputDecoration(
                labelText: '¿Cuál es?',
                hintText: 'Media Maratón, triatlón, marcha…',
                labelStyle: TextStyle(color: skin.textMuted),
              ),
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: () async {
                final hoy = DateTime.now();
                final d = await showDatePicker(
                  context: context,
                  initialDate: hoy.add(const Duration(days: 30)),
                  firstDate: hoy,
                  lastDate: hoy.add(const Duration(days: 730)),
                );
                if (d != null) setState(() => _fecha = d);
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: '¿Qué día?',
                  labelStyle: TextStyle(color: skin.textMuted),
                ),
                child: Text(
                  _fecha == null
                      ? 'Elegir fecha'
                      : fechaLarga(_fecha!.toIso8601String().split('T')[0]),
                  style: TextStyle(
                      color: _fecha == null ? skin.textMuted : skin.textPrimary),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _distancia,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(color: skin.textPrimary),
              decoration: InputDecoration(
                labelText: '¿Cuántos km? (opcional)',
                hintText: '21,1',
                labelStyle: TextStyle(color: skin.textMuted),
              ),
            ),
            const SizedBox(height: 16),
            // La pregunta clave, en SU idioma. De aquí sale el rol técnico que
            // usa la metodología del entrenador.
            Text('¿Vas a por ella?',
                style: TextStyle(color: skin.textPrimary,
                    fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text('Esto cambia cómo preparo tu plan para ese día.',
                style: TextStyle(color: skin.textMuted, fontSize: 12)),
            const SizedBox(height: 6),
            // Botones compactos en vez de RadioListTile: con la letra grande del
            // sistema, las dos filas de radio no cabían y solo se veía la
            // primera opción — parecía que no había alternativa.
            _opcion(skin, true,  'Sí, quiero rendir al máximo'),
            const SizedBox(height: 6),
            _opcion(skin, false, 'No, la corro de preparación'),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: skin.error, fontSize: 13)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.of(context).pop(),
          child: Text('Cancelar', style: TextStyle(color: skin.textMuted)),
        ),
        ElevatedButton(
          onPressed: _guardando ? null : () => _guardar(context),
          style: ElevatedButton.styleFrom(
              backgroundColor: skin.accent, foregroundColor: skin.background),
          child: _guardando
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Apuntar'),
        ),
      ],
    );
  }
}
