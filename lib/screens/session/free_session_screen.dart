import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/skin_provider.dart';
import '../../providers/workout_provider.dart';
import '../../core/network/api_client.dart';
import '../../models/sport.dart';

/// ENTRENAMIENTO LIBRE — el deportista entrena algo que no está en el plan.
///
/// Hoy no le apetece la serie que le tocaba, o va a salir en bici con unos amigos,
/// o se va a dar una caminata larga. Sin esto, ese entreno no existía para nadie:
/// ni cuenta, ni se ve en el panel, ni el agente se entera. Y un entrenamiento que
/// no queda registrado es un entrenamiento que el entrenador no puede tener en
/// cuenta la semana siguiente.
///
/// Solo las especialidades de la casa. No abrimos un catálogo de 200 deportes.
class FreeSessionScreen extends ConsumerStatefulWidget {
  const FreeSessionScreen({super.key});

  @override
  ConsumerState<FreeSessionScreen> createState() => _FreeSessionScreenState();
}

class _FreeSessionScreenState extends ConsumerState<FreeSessionScreen> {
  Sport? _elegido;
  bool _creando = false;
  String? _error;

  Future<void> _empezar() async {
    if (_elegido == null || _creando) return;
    setState(() { _creando = true; _error = null; });
    try {
      final api  = ref.read(apiClientProvider);
      final data = await api.createFreeSession(_elegido!.api);
      final id   = data['session']?['id'] as String?;
      if (id == null) throw Exception('El servidor no devolvió la sesión');

      // Deja la sesión cargada para que la pantalla de sesión ya sepa el deporte.
      ref.read(activeSessionProvider.notifier).setFreeSession(data['session'] as Map<String, dynamic>);
      if (!mounted) return;
      // replace: al volver atrás no se vuelve al selector, se vuelve al inicio.
      context.pushReplacement('/session/$id');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _creando = false;
        _error = 'No he podido crear el entrenamiento. Revisa la conexión.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = ref.watch(skinProvider).skin;

    return Scaffold(
      backgroundColor: skin.background,
      appBar: AppBar(
        backgroundColor: skin.backgroundSecondary,
        leading: IconButton(
          icon: Icon(Icons.close, color: skin.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'ENTRENAMIENTO LIBRE',
          style: TextStyle(color: skin.textPrimary, letterSpacing: 2, fontSize: 14),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Text(
                '¿Qué vas a hacer hoy?',
                style: TextStyle(
                  color: skin.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Este entreno cuenta como tuyo y lo verá tu entrenador, '
                'pero no sustituye a la sesión del plan.',
                style: TextStyle(color: skin.textMuted, fontSize: 13, height: 1.4),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: Sport.especialidades.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final s = Sport.especialidades[i];
                  final sel = _elegido == s;
                  return InkWell(
                    onTap: _creando ? null : () => setState(() => _elegido = s),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                      decoration: BoxDecoration(
                        color: sel ? skin.accent.withValues(alpha: 0.14) : skin.backgroundCard,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: sel ? skin.accent : skin.border,
                          width: sel ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(s.icon, color: sel ? skin.accent : skin.textMuted, size: 26),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.label,
                                  style: TextStyle(
                                    color: skin.textPrimary,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _queSeMide(s),
                                  style: TextStyle(color: skin.textMuted, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          if (sel) Icon(Icons.check_circle, color: skin.accent, size: 22),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: skin.error, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _elegido == null || _creando ? null : _empezar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: skin.accent,
                    disabledBackgroundColor: skin.border,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _creando
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                        )
                      : Text(
                          'EMPEZAR',
                          style: TextStyle(
                            color: skin.background,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Que el deportista sepa de antemano qué va a ver mientras entrena.
  String _queSeMide(Sport s) => switch (s) {
        Sport.running  => 'Ritmo min/km, distancia y recorrido',
        Sport.trail    => 'Ritmo min/km, desnivel y recorrido',
        Sport.ciclismo => 'Velocidad km/h, distancia y recorrido',
        Sport.natacion => 'Ritmo /100 m y metros',
        Sport.fuerza   => 'Tiempo y pulso (sin GPS)',
        Sport.otro     => 'Tiempo y distancia',
      };
}
