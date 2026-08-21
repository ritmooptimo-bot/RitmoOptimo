import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_client.dart';
import '../core/session/aviso_zona.dart';

/// Las zonas de frecuencia cardiaca del deportista, en pulsaciones.
///
/// ⚠️ DEVUELVE null CUANDO NO SE PUEDEN SABER —sin red, o sin una FC máxima
/// utilizable— y eso es una respuesta, no un fallo: sin rangos no se avisa de
/// nada. Un rango inventado es peor que ninguno, porque suena igual de seguro.
///
/// ⚠️ Y NO SIRVEN PARA LA ESCALA R. La de Raúl es de percepción («sin reloj ni
/// pulsómetro»): estos rangos solo se aplican a los bloques marcados como
/// `zone_escala == 'fc'` (migración 090).
class ZonasFc {
  final List<RangoFc> zonas;
  final int fcMaxBpm;

  /// De dónde sale la FC máxima: `test_campo`, `sesion_dura`, `declarada` o
  /// `estimada_edad`. El deportista tiene derecho a saber sobre qué número se le
  /// está midiendo — no es lo mismo su test que una fórmula.
  final String procedencia;
  final bool esEstimacion;
  final String? explicacion;

  /// ⚠️ LAS ZONAS DEL ENTRENADOR (R0…R3+) EN PULSACIONES.
  ///
  /// Sin esto, un plan escrito entero en la escala R —que es como escribe el
  /// suyo— dejaba a la app MUDA: ni decía la zona ni podía avisar de nada.
  /// Salen de las fracciones de FC de reserva de sus propias zonas, aplicadas
  /// a la máxima y el reposo medidos de este deportista. Son una ESTIMACIÓN
  /// mientras no haya test de campo, y por eso van marcadas.
  final List<RangoFc> zonasEntrenador;
  final String? procedenciaEntrenador;

  const ZonasFc({
    required this.zonas,
    required this.fcMaxBpm,
    required this.procedencia,
    required this.esEstimacion,
    this.explicacion,
    this.zonasEntrenador = const [],
    this.procedenciaEntrenador,
  });
}

final zonasFcProvider = FutureProvider.autoDispose<ZonasFc?>((ref) async {
  final api = ref.read(apiClientProvider);
  try {
    final j = await api.getHrZones();
    final max = j['max_hr'];
    final raw = j['zones'];
    if (max is! Map || raw is! List || raw.isEmpty) return null;

    final zonas = raw.map((e) {
      final z = Map<String, dynamic>.from(e as Map);
      return RangoFc(
        desde: (z['from'] as num).toInt(),
        hasta: z['to'] == null ? null : (z['to'] as num).toInt(),
        nombre: (z['name'] ?? '').toString(),
      );
    }).toList();

    // Las del entrenador, si el servidor las manda. Se marcan como estimación
    // porque lo son: la app lo dirá en voz alta al anunciar el bloque.
    final rawR = j['zonas_entrenador'];
    final estimadas = j['zonas_entrenador_es_estimacion'] == true;
    final zonasR = rawR is List
        ? rawR
            .map((e) => Map<String, dynamic>.from(e as Map))
            .where((e) => e['from'] != null && e['to'] != null)
            .map((e) => RangoFc(
                  desde: (e['from'] as num).toInt(),
                  hasta: (e['to'] as num).toInt(),
                  nombre: (e['name'] ?? '').toString(),
                  esEstimacion: estimadas,
                ))
            .toList()
        : <RangoFc>[];

    return ZonasFc(
      zonas: zonas,
      zonasEntrenador: zonasR,
      procedenciaEntrenador: j['zonas_entrenador_procedencia']?.toString(),
      fcMaxBpm: (max['bpm'] as num).toInt(),
      procedencia: (max['source'] ?? 'estimada_edad').toString(),
      esEstimacion: max['is_estimate'] == true,
      explicacion: max['why']?.toString(),
    );
  } catch (_) {
    // Sin zonas la sesión funciona igual: simplemente no avisa por pulsaciones.
    return null;
  }
});

/// La equivalencia entre la escala del entrenador y las pulsaciones, PARA ESTE
/// deportista.
///
/// ⚠️ Solo llegan las filas UTILIZABLES: con una sola sesión detrás no se le
/// dice nada a nadie, igual que con el e1RM. Y cada una trae si manda el
/// entrenador (firmada) o si es lo que él suele hacer (observada) — de eso
/// depende que la app corrija o describa.
final equivalenciaZonasProvider = FutureProvider.autoDispose<List<RangoFc>>((ref) async {
  final api = ref.read(apiClientProvider);
  try {
    final j = await api.getZoneEquivalence();
    final raw = j['equivalence'];
    if (raw is! List) return const [];
    return raw
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((e) => e['usable'] == true && e['from'] != null && e['to'] != null)
        .map((e) => RangoFc(
              desde: (e['from'] as num).toInt(),
              hasta: (e['to'] as num).toInt(),
              nombre: (e['label'] ?? '').toString(),
              mandaElEntrenador: e['manda_el_entrenador'] == true,
            ))
        .toList();
  } catch (_) {
    return const [];
  }
});
