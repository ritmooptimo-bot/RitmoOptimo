import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_client.dart';

/// Un profesional del equipo del deportista.
class Profesional {
  final String nombre;
  final String especialidad;

  /// Si planifica CARGA es el entrenador de la disciplina: el que responde de
  /// que el deportista mejore sin romperse, y el que más veces va a citar el
  /// agente. Por eso va delante.
  final bool planificaCarga;

  const Profesional(this.nombre, this.especialidad, this.planificaCarga);

  factory Profesional.fromJson(Map<String, dynamic> j) => Profesional(
        (j['name'] ?? '').toString(),
        (j['specialty'] ?? 'Entrenamiento').toString(),
        j['plans_load'] == true,
      );
}

/// El equipo que lleva a este deportista.
///
/// ⚠️ Nace del salto a VARIOS profesionales: Raúl (trail), un oro olímpico en
/// ciclismo, Chamba (ultratrail), fuerza, y después nutrición y psicología. Con
/// uno solo bastaba con "Entrenador: X". Con varios, la atribución deja de ser
/// cosmética y pasa a ser el producto: el deportista tiene derecho a saber de
/// quién es el criterio que está siguiendo.
final equipoProvider = FutureProvider.autoDispose<List<Profesional>>((ref) async {
  final api = ref.read(apiClientProvider);
  try {
    return (await api.getTeam()).map(Profesional.fromJson).toList();
  } catch (_) {
    // Que no se vea el equipo no puede romper una pantalla: se devuelve vacío y
    // cada sitio decide qué enseñar mientras tanto.
    return const [];
  }
});

/// Cómo se resume el equipo en una línea de cabecera.
///
/// Con un entrenador: "Entrenador: Raúl" — como siempre.
/// Con varios:        "Raúl · Ana (Nutrición)".
/// El entrenador de la disciplina va SIEMPRE delante.
String resumenEquipo(List<Profesional> equipo) {
  if (equipo.isEmpty) return '';
  final ordenado = [...equipo]
    ..sort((a, b) => (b.planificaCarga ? 1 : 0) - (a.planificaCarga ? 1 : 0));
  if (ordenado.length == 1) {
    final p = ordenado.first;
    return p.planificaCarga ? 'Entrenador: ${p.nombre}' : '${p.nombre} · ${p.especialidad}';
  }
  // Dos como mucho en la cabecera: con cinco profesionales, la línea se
  // convierte en una lista ilegible justo donde hay menos sitio (y con la letra
  // del sistema al 180 % no cabe ni uno).
  final visibles = ordenado.take(2)
      .map((p) => p.planificaCarga ? p.nombre : '${p.nombre} (${p.especialidad})')
      .join(' · ');
  final resto = ordenado.length - 2;
  return resto > 0 ? '$visibles +$resto' : visibles;
}
