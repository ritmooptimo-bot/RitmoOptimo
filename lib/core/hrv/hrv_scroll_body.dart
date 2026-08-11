import 'package:flutter/material.dart';

/// Cuerpo de las pantallas de medición de HRV/FC: **centrado cuando cabe, con
/// scroll cuando no**.
///
/// ⚠️ POR QUÉ EXISTE (11/08/2026, medición real de David con la banda).
///
/// Las dos pantallas de medición pintaban su contenido en un `Column` dentro de
/// un `Padding`, sin scroll. Con señal limpia entraba justo. Pero cuando la
/// medición sale sucia, el aviso pasa de una línea a **cinco**:
///
///   «"Señal ruidosa" = tu banda manda algunos latidos con error. Los
///   corregimos, así que este HRV es una ESTIMACIÓN (no exacto)…»
///
/// Ese texto empuja hacia abajo **USAR VALORES** y **Repetir**, que es justo lo
/// que necesitas cuando la medición sale mal — y no había forma de llegar a
/// ellos. Con la letra del sistema al 180 % pasa incluso con el aviso corto.
///
/// Y es la trampa fea de Flutter: **un `Column` que no cabe recorta y sigue**.
/// `flutter analyze` no dice nada, en el emulador con letra normal se ve bien, y
/// el fallo solo aparece en el móvil de alguien que ya está midiendo.
///
/// El `minHeight` es lo que conserva el centrado: sin él, con poco contenido
/// todo se pegaría arriba y las pantallas de medición quedarían descolgadas.
class HrvScrollBody extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;

  const HrvScrollBody({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Sin el clamp, en una pantalla más baja que el propio padding saldría
        // un minHeight negativo y reventaría el layout.
        final alto = (constraints.maxHeight - padding.vertical)
            .clamp(0.0, double.infinity);
        return SingleChildScrollView(
          padding: padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: alto),
            // Center + Column(min) hace el mismo trabajo que
            // `mainAxisAlignment: center` pero sin exigirle al Column que ocupe
            // un alto que aquí no está acotado.
            child: Center(child: child),
          ),
        );
      },
    );
  }
}
