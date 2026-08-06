import 'package:flutter/material.dart';

import '../../core/audio/audio_cue_service.dart';

/// Elegir la voz que guía la sesión.
///
/// ⚠️ Por qué no pone "hombre" y "mujer": los motores de voz de Android NO
/// dicen el sexo de cada voz. Solo dan nombres tipo "es-es-x-eef-local". Se
/// podría adivinar por la letra, pero acertaría a veces y a veces no, y un
/// cartel que dice "mujer" sobre una voz de hombre es peor que no poner nada.
///
/// Así que se hace lo que sí es honesto: se listan las que el móvil tiene de
/// verdad y el atleta las ESCUCHA y elige la que le guste. Es un botón más y
/// no hay forma de equivocarse.
class VoicePickerSheet extends StatefulWidget {
  final AudioCueService audio;
  const VoicePickerSheet({super.key, required this.audio});

  static Future<void> mostrar(BuildContext context, AudioCueService audio) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VoicePickerSheet(audio: audio),
    );
  }

  @override
  State<VoicePickerSheet> createState() => _VoicePickerSheetState();
}

class _VoicePickerSheetState extends State<VoicePickerSheet> {
  static const _frase =
      'Kilómetro 1. Último kilómetro en 5 minutos 30 segundos. Buen ritmo.';

  List<Map<String, String>> _voces = [];
  String? _elegida;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    await widget.audio.init();
    final v = await widget.audio.vocesDisponibles();
    if (!mounted) return;
    setState(() { _voces = v; _cargando = false; });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      expand: false,
      builder: (context, scroll) => Container(
        decoration: BoxDecoration(
          color: t.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade600,
                borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Voz de la sesión', style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(
                  'Escúchalas y quédate con la que prefieras. Es la voz que te '
                  'irá guiando durante el entrenamiento.',
                  style: t.textTheme.bodySmall?.copyWith(color: Colors.grey.shade400),
                ),
              ]),
            ),
            const Divider(height: 20),
            Expanded(
              child: _cargando
                  ? const Center(child: CircularProgressIndicator())
                  : _voces.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Tu móvil no ofrece voces en español para elegir. Se usará '
                            'la voz que tengas configurada en el sistema.',
                            style: t.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade400),
                          ))
                      : ListView.builder(
                          controller: scroll,
                          itemCount: _voces.length,
                          itemBuilder: (_, i) {
                            final v = _voces[i];
                            final sel = _elegida == v['name'];
                            return ListTile(
                              leading: IconButton(
                                icon: const Icon(Icons.play_circle_outline, size: 30),
                                tooltip: 'Escuchar',
                                onPressed: () => widget.audio.probarVoz(v, _frase),
                              ),
                              title: Text('Voz ${i + 1}'),
                              subtitle: Text(v['name'] ?? '',
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: t.textTheme.bodySmall?.copyWith(color: Colors.grey.shade500)),
                              trailing: sel
                                  ? const Icon(Icons.check_circle, color: Colors.green)
                                  : null,
                              onTap: () {
                                setState(() => _elegida = v['name']);
                                widget.audio.probarVoz(v, _frase);
                              },
                            );
                          },
                        ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _elegida == null
                        ? null
                        : () async {
                            final v = _voces.firstWhere((x) => x['name'] == _elegida);
                            await widget.audio.guardarVoz(v);
                            if (context.mounted) Navigator.of(context).pop();
                          },
                    child: const Text('Usar esta voz'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
