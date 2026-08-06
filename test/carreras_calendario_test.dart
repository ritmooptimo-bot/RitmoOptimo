// ═══════════════════════════════════════════════════════════════
//  El trofeo en el calendario del plan
//
//  El calendario solo sabía de entrenamientos: el día de su carrera se veía
//  igual que un martes cualquiera. Ahora lleva marca, pero SOLO el objetivo
//  lleva trofeo: David tiene 10 carreras apuntadas y únicamente 2 son sus
//  objetivos. Marcarlas todas igual llenaría el mes de trofeos y ninguno diría
//  nada — y el rojo, además, ya significa "sesión fallada" en ese calendario.
//
//  Lo que se prueba aquí es el reparto por días, que es donde está el riesgo:
//  el 4 de octubre tiene DOS carreras (Milla Verde en Chiclana y Cross del
//  Colorado en Conil) y la celda solo puede pintar una.
// ═══════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:ritmooptimo_mobile/screens/plan/competitions_sheet.dart';

// El calendario real de David, tal y como lo devuelve el backend.
final _datos = {
  'competitions': [
    {'name': 'Carrera nocturna La Barrosa', 'fecha': '2026-08-29', 'role': 'popular'},
    {'name': 'Traxnochadora', 'fecha': '2026-09-19', 'role': 'popular'},
    {'name': 'Carrera de Chiclana por la Igualdad', 'fecha': '2026-09-27', 'role': 'popular'},
    {'name': 'Milla Verde', 'fecha': '2026-10-04', 'role': 'popular'},
    {'name': 'Cross del Colorado', 'fecha': '2026-10-04', 'role': 'popular'},
    {'name': 'Carrera Athletica Chiclana', 'fecha': '2026-10-18', 'role': 'popular'},
    {'name': 'Cross Pinar de Hierro', 'fecha': '2026-11-08', 'role': 'primario'},
    {'name': 'Carrera Urbana con Varias Cuestas', 'fecha': '2026-11-22', 'role': 'popular'},
    {'name': 'Cross Pinar de Hierro', 'fecha': '2026-12-13', 'role': 'popular'},
    {'name': 'San Silvestre', 'fecha': '2026-12-30', 'role': 'primario'},
  ],
};

void main() {
  group('carrerasDelMes', () {
    test('noviembre: el día 8 es su objetivo, el 22 no', () {
      final m = carrerasDelMes(_datos, DateTime(2026, 11));

      expect(m.length, 2);
      expect(m[8]!.nombre, 'Cross Pinar de Hierro');
      expect(m[8]!.esObjetivo, isTrue, reason: 'el 8 de noviembre es su objetivo');
      expect(m[22]!.esObjetivo, isFalse, reason: 'la urbana es preparación');
    });

    test('solo trae el mes que se está viendo', () {
      expect(carrerasDelMes(_datos, DateTime(2026, 9)).keys.toList()..sort(), [19, 27]);
      expect(carrerasDelMes(_datos, DateTime(2026, 7)), isEmpty);
      // Mismo mes, otro año: no cuenta.
      expect(carrerasDelMes(_datos, DateTime(2025, 11)), isEmpty);
    });

    test('dos carreras el mismo día: la celda no se duplica', () {
      final m = carrerasDelMes(_datos, DateTime(2026, 10));
      expect(m[4], isNotNull);
      expect(m.length, 2, reason: 'día 4 (dos carreras, una celda) y día 18');
    });

    test('si una de las dos del día es el objetivo, gana el objetivo', () {
      // Da igual el orden en que lleguen: el trofeo no lo tapa una popular.
      for (final orden in [
        [
          {'name': 'Popular de turno', 'fecha': '2026-10-04', 'role': 'popular'},
          {'name': 'La importante', 'fecha': '2026-10-04', 'role': 'primario'},
        ],
        [
          {'name': 'La importante', 'fecha': '2026-10-04', 'role': 'primario'},
          {'name': 'Popular de turno', 'fecha': '2026-10-04', 'role': 'popular'},
        ],
      ]) {
        final m = carrerasDelMes({'competitions': orden}, DateTime(2026, 10));
        expect(m[4]!.nombre, 'La importante');
        expect(m[4]!.esObjetivo, isTrue);
      }
    });

    test('sin datos o con basura, el calendario se pinta igual', () {
      expect(carrerasDelMes(null, DateTime(2026, 11)), isEmpty);
      expect(carrerasDelMes({}, DateTime(2026, 11)), isEmpty);
      expect(carrerasDelMes({'competitions': []}, DateTime(2026, 11)), isEmpty);
      // Una fecha ilegible no puede tumbar la pantalla del plan.
      expect(
        carrerasDelMes({
          'competitions': [
            {'name': 'Rota', 'fecha': 'mañana', 'role': 'primario'},
            {'name': 'Buena', 'fecha': '2026-11-08', 'role': 'primario'},
          ],
        }, DateTime(2026, 11)).length,
        1,
      );
    });

    test('una competición sin nombre no deja la celda en blanco', () {
      final m = carrerasDelMes({
        'competitions': [{'fecha': '2026-11-08', 'role': 'primario'}],
      }, DateTime(2026, 11));
      expect(m[8]!.nombre, 'Competición');
    });
  });

  // Al tocar un día, se ve LO DE ESE DÍA. Antes, tocar la carrera del 29 abría
  // el listado de las diez competiciones de la temporada.
  group('carrerasDelDia', () {
    test('devuelve solo la carrera de ese día, con sus datos', () {
      final l = carrerasDelDia(_datos, DateTime(2026, 8, 29));
      expect(l.length, 1);
      expect(l.first.nombre, 'Carrera nocturna La Barrosa');
      expect(l.first.esObjetivo, isFalse);   // preparación, y aun así se ve
      expect(l.first.fecha, '2026-08-29');
    });

    test('un día sin carrera no devuelve nada', () {
      expect(carrerasDelDia(_datos, DateTime(2026, 8, 28)), isEmpty);
      expect(carrerasDelDia(null, DateTime(2026, 8, 29)), isEmpty);
    });

    test('el 4 de octubre devuelve LAS DOS', () {
      final l = carrerasDelDia(_datos, DateTime(2026, 10, 4));
      expect(l.length, 2);
      expect(l.map((c) => c.nombre).toSet(), {'Milla Verde', 'Cross del Colorado'});
    });

    test('con varias el mismo día, el objetivo va primero', () {
      final l = carrerasDelDia({
        'competitions': [
          {'name': 'Popular', 'fecha': '2026-10-04', 'role': 'popular'},
          {'name': 'La importante', 'fecha': '2026-10-04', 'role': 'primario'},
        ],
      }, DateTime(2026, 10, 4));
      expect(l.first.nombre, 'La importante');
    });
  });

  group('cuánto falta para la carrera', () {
    // Se cuenta por DÍAS de calendario, no por horas: una carrera mañana a las
    // 9:00 vista hoy a las 22:00 tiene que decir "Es mañana", no "Faltan 0 días".
    String faltaPara(Duration d) {
      final f = DateTime.now().add(d);
      final iso = '${f.year}-${f.month.toString().padLeft(2, '0')}-${f.day.toString().padLeft(2, '0')}';
      return CarreraDelDia('X', false, fecha: iso).cuantoFalta;
    }

    test('hoy, mañana y dentro de un tiempo', () {
      expect(faltaPara(Duration.zero), 'ES HOY');
      expect(faltaPara(const Duration(days: 1)), 'Es mañana');
      expect(faltaPara(const Duration(days: 23)), 'Faltan 23 días');
    });

    test('una carrera pasada no dice nada', () {
      expect(faltaPara(const Duration(days: -5)), '');
    });

    test('sin fecha legible, tampoco inventa', () {
      expect(const CarreraDelDia('X', false, fecha: 'mañana').cuantoFalta, '');
      expect(const CarreraDelDia('X', false).cuantoFalta, '');
    });
  });
}
