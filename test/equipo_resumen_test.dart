import 'package:flutter_test/flutter_test.dart';
import 'package:ritmooptimo_mobile/providers/equipo_provider.dart';

/// La cabecera tiene que decir DE QUIÉN es el criterio, y caber.
///
/// Con cinco profesionales (entrenador de la disciplina + fuerza + nutrición +
/// psicología + fisio) una lista completa no entra en una línea — y con la letra
/// del sistema al 180 %, que es la del móvil de pruebas, no entra ni uno.
void main() {
  const raul  = Profesional('Raúl', 'Entrenamiento', true);
  const juanm = Profesional('Juan Manuel', 'Entrenamiento', true);
  const ana   = Profesional('Ana', 'Nutrición', false);
  const luis  = Profesional('Luis', 'Psicología deportiva', false);

  test('sin equipo no inventa nada', () {
    expect(resumenEquipo(const []), '');
  });

  test('un entrenador: como toda la vida', () {
    expect(resumenEquipo(const [raul]), 'Entrenador: Raúl');
  });

  test('un especialista solo: con su especialidad', () {
    expect(resumenEquipo(const [ana]), 'Ana · Nutrición');
  });

  test('el ENTRENADOR va delante aunque llegue el último', () {
    expect(resumenEquipo(const [ana, raul]), startsWith('Raúl'));
  });

  test('entrenador + nutricionista: se ven los dos', () {
    expect(resumenEquipo(const [raul, ana]), 'Raúl · Ana (Nutrición)');
  });

  test('con cinco, dos y el resto contado — no una lista ilegible', () {
    final r = resumenEquipo(const [raul, juanm, ana, luis]);
    expect(r, 'Raúl · Juan Manuel +2');
    expect(r.length < 40, isTrue, reason: 'tiene que caber en la cabecera: "$r"');
  });
}
