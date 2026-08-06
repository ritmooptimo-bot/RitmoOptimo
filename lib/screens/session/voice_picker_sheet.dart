import 'package:flutter/material.dart';

import '../../core/audio/audio_cue_service.dart';

/// Elegir la voz que guía la sesión.
///
/// ⚠️ POR QUÉ NO PONE "HOMBRE" Y "MUJER":
/// Android NO lo dice. Su clase `Voice` expone nombre, idioma, calidad,
/// latencia y si necesita internet — y nada más. No hay campo de género en
/// ninguna versión. Se podría adivinar por la letra del código
/// ("es-es-x-eef-local") y acertaría unas veces sí y otras no; un cartel que
/// dice "mujer" sobre una voz de hombre es peor que no poner nada.
///
/// Lo que sí se puede es quitar de en medio el galimatías: se descartan las
/// voces que no están instaladas (que era justo por lo que el botón de
/// escuchar no sonaba), se agrupan por acento y se numeran. El atleta las
/// escucha y elige. Un botón más y no hay forma de equivocarse.
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
      'Kilómetro 3. Último kilómetro en 5 minutos 30 segundos. Buen ritmo, sigue así.';

  List<Map<String, String>> _voces = [];
  String? _elegida;
  String? _sonando;
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

  /// "España · voz 2" — el número es su orden DENTRO de su acento, para que no
  /// salga un salto raro (voz 1, voz 5, voz 9) al haber filtrado las que no
  /// están instaladas.
  String _titulo(int indice) {
    final v = _voces[indice];
    final zona = v['zona'] == 'espana' ? 'España' : 'Latinoamérica';
    final n = _voces.take(indice + 1).where((x) => x['zona'] == v['zona']).length;
    return '$zona · voz $n';
  }

  Future<void> _escuchar(Map<String, String> v) async {
    setState(() => _sonando = v['name']);
    final ok = await widget.audio.probarVoz(v, _frase);
    if (!mounted) return;
    setState(() => _sonando = null);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Esa voz no ha podido sonar. Prueba con otra.'),
        duration: Duration(seconds: 3),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.66,
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
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Voz de la sesión',
                    style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(
                  'Pulsa ▶ para escuchar cada una y quédate con la que prefieras. '
                  'Es la voz que te irá guiando mientras entrenas.',
                  style: t.textTheme.bodySmall?.copyWith(color: Colors.grey.shade400, height: 1.35),
                ),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: _cargando
                  ? const Center(child: CircularProgressIndicator())
                  : _voces.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Tu móvil no tiene ninguna voz en español instalada. Se usará '
                            'la que tengas configurada en los ajustes del teléfono.\n\n'
                            'Puedes descargar más en Ajustes › Idiomas › Texto a voz.',
                            style: t.textTheme.bodyMedium?.copyWith(
                                color: Colors.grey.shade400, height: 1.4),
                          ))
                      : ListView.separated(
                          controller: scroll,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          itemCount: _voces.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, indent: 68),
                          itemBuilder: (_, i) {
                            final v = _voces[i];
                            final sel = _elegida == v['name'];
                            final suena = _sonando == v['name'];
                            final red = v['necesitaRed'] == 'si';
                            return ListTile(
                              leading: IconButton(
                                icon: suena
                                    ? const SizedBox(width: 26, height: 26,
                                        child: CircularProgressIndicator(strokeWidth: 2.5))
                                    : const Icon(Icons.play_circle_outline, size: 32),
                                tooltip: 'Escuchar',
                                onPressed: suena ? null : () => _escuchar(v),
                              ),
                              title: Text(_titulo(i),
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: red
                                  ? Text('Necesita internet',
                                      style: t.textTheme.bodySmall
                                          ?.copyWith(color: Colors.orange.shade300))
                                  : null,
                              trailing: sel
                                  ? const Icon(Icons.check_circle, color: Colors.green, size: 26)
                                  : null,
                              onTap: () {
                                setState(() => _elegida = v['name']);
                                _escuchar(v);
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
