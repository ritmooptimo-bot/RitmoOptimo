import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../config/skins/skin_config.dart';
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
        // "Revisa la conexión" era mentira cuando el servidor SÍ respondía (un
        // 400, un 409, un 500…). Se dice lo que ha pasado de verdad: sin esto,
        // diagnosticar un fallo en la calle es imposible.
        _error = _explicar(e);
      });
    }
  }

  String _explicar(Object e) {
    if (e is DioException) {
      final code = e.response?.statusCode;
      final data = e.response?.data;
      final msg = data is Map ? (data['error'] ?? data['message']) : null;
      if (code != null) {
        return msg != null
            ? 'El servidor ha rechazado la petición (HTTP $code):\n$msg'
            : 'El servidor ha rechazado la petición (HTTP $code).';
      }
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return 'El servidor no responde (tiempo agotado). Reinténtalo.';
        case DioExceptionType.connectionError:
          return 'Sin conexión con el servidor. Revisa los datos o la wifi.';
        default:
          return 'Error de red: ${e.message ?? e.type.name}';
      }
    }
    return 'No he podido crear el entrenamiento: $e';
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
            // El título y la explicación van DENTRO del scroll, no encima de él.
            //
            // Antes eran hijos fijos del Column: con la letra del sistema al
            // 180 %, el párrafo ocupaba cuatro renglones y, junto al título, se
            // quedaba con un tercio de la pantalla PARA SIEMPRE. A los seis
            // deportes les sobraban tres huecos y medio, y había que adivinar
            // que la lista seguía. Ahora se deslizan al bajar.
            //
            // Solo el botón se queda quieto, porque es la acción de la pantalla.
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                itemCount: Sport.especialidades.length + 1,
                separatorBuilder: (_, i) => SizedBox(height: i == 0 ? 20 : 10),
                itemBuilder: (_, idx) {
                  if (idx == 0) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '¿Qué vas a hacer hoy?',
                          style: TextStyle(
                            color: skin.textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Este entreno cuenta como tuyo y lo verá tu entrenador, '
                          'pero no sustituye a la sesión del plan.',
                          style: TextStyle(color: skin.textMuted, fontSize: 13, height: 1.4),
                        ),
                      ],
                    );
                  }
                  final i = idx - 1;
                  return _tarjetaDeporte(i, skin);
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
            // Una línea que separa el botón de la lista. Sin ella, la última
            // tarjeta se cortaba a ras del botón y parecía un fallo de dibujo.
            Divider(height: 1, thickness: 1, color: skin.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: SizedBox(
                width: double.infinity,
                // Alto MÍNIMO, no fijo: con la letra grande, 54 px recortaban el
                // texto del botón.
                child: ElevatedButton(
                  onPressed: _elegido == null || _creando ? null : _empezar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: skin.accent,
                    disabledBackgroundColor: skin.border,
                    minimumSize: const Size.fromHeight(54),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                          'Empezar',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: skin.background,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
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

  /// Una opción de deporte. Sale del `itemBuilder` para que la cabecera pueda
  /// viajar como primer elemento de la misma lista.
  Widget _tarjetaDeporte(int i, SkinConfig skin) {
    final s   = Sport.especialidades[i];
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
  }

  /// Que el deportista sepa de antemano qué va a ver mientras entrena.
  String _queSeMide(Sport s) => switch (s) {
        Sport.running  => 'Ritmo min/km, distancia y recorrido',
        Sport.trail    => 'Ritmo min/km, desnivel y recorrido',
        Sport.ciclismo => 'Velocidad km/h, distancia y recorrido',
        Sport.natacion => 'Ritmo /100 m y metros',
        Sport.fuerza   => 'Tiempo y pulso (sin GPS)',
        Sport.otro     => 'Caminata o marcha: ritmo, distancia y recorrido',
      };
}
