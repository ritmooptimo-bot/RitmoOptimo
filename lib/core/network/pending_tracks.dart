import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';

/// RECORRIDOS PENDIENTES DE SUBIR — la red de seguridad del entrenamiento.
///
/// El 20/07/2026 un atleta caminó 562 metros con el GPS grabando perfectamente,
/// volvió a casa y al guardar el servidor devolvió un 500. El recorrido vivía
/// SOLO en la memoria de la pantalla: al salir de ella se perdió entero — la
/// ruta, los ritmos y el comentario. Media hora de entrenamiento por un fallo de
/// red de tres segundos.
///
/// Ahora el recorrido se escribe en el móvil ANTES de intentar subirlo, y ahí se
/// queda hasta que el servidor confirme que lo tiene. Si falla la subida, si se
/// cierra la app, si se va la batería: el track sigue en el teléfono y se
/// reintenta solo al abrir la app.
class PendingTracks {
  static const _clave = 'recorridos_pendientes';

  static Future<Map<String, dynamic>> _leer() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_clave);
    if (raw == null || raw.isEmpty) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  static Future<void> _escribir(Map<String, dynamic> m) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_clave, jsonEncode(m));
  }

  /// Guarda el recorrido en el móvil antes de intentar subirlo.
  static Future<void> guardar(String sessionId, Map<String, dynamic> payload) async {
    final m = await _leer();
    m[sessionId] = payload;
    await _escribir(m);
  }

  /// El servidor ya lo tiene: se puede soltar.
  static Future<void> borrar(String sessionId) async {
    final m = await _leer();
    if (m.remove(sessionId) != null) await _escribir(m);
  }

  static Future<int> cuantosPendientes() async => (await _leer()).length;

  /// Reintenta todos los pendientes. Se llama al abrir la app: si el atleta
  /// guardó sin recorrido porque no había cobertura, al volver a casa con wifi
  /// su ruta sube sola y aparece en el resumen y en el panel del entrenador.
  static Future<int> reintentarTodo(ApiClient api) async {
    final m = await _leer();
    if (m.isEmpty) return 0;
    var subidos = 0;
    for (final entry in m.entries.toList()) {
      try {
        await api.postGPSTrack(entry.key, Map<String, dynamic>.from(entry.value as Map));
        await borrar(entry.key);
        subidos++;
      } catch (_) {
        // Sigue pendiente: se reintentará la próxima vez. Nunca se descarta.
      }
    }
    return subidos;
  }
}
