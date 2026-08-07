import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/skin_provider.dart';

/// La rueda dentada que lleva a Ajustes, en la cabecera de TODAS las pestañas.
///
/// Antes había un único acceso en toda la app: un icono de 20 px en una esquina
/// de Inicio, que sobrevivía de cuando Ajustes era una pestaña de la barra
/// inferior. Al entrar el Chat perdió su sitio y quedó ahí colgando. David dejó
/// de encontrar dónde cambiar el color de la app — y no porque se hubiera roto,
/// sino porque el camino se había quedado escondido.
///
/// Va en un solo fichero a propósito: cinco copias del mismo botón acaban
/// divergiendo, y entonces el engranaje se ve distinto según la pestaña.
class BotonAjustes extends ConsumerWidget {
  /// En Inicio el sitio es estrecho —comparte fila con el estado del día y el
  /// aviso de alertas— y ahí el icono va compacto. En las barras normales cabe
  /// a tamaño de siempre.
  final bool compacto;

  const BotonAjustes({super.key, this.compacto = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin = ref.watch(activeSkinProvider);
    return IconButton(
      icon: Icon(Icons.settings_outlined,
          color: skin.textSecondary, size: compacto ? 20 : 22),
      tooltip: 'Ajustes',
      padding: compacto ? EdgeInsets.zero : null,
      visualDensity: compacto ? VisualDensity.compact : null,
      constraints: compacto
          ? const BoxConstraints(minWidth: 32, minHeight: 32)
          : null,
      // push, no go: Ajustes se abre ENCIMA de la pestaña en la que estabas, y
      // al volver sigues donde lo dejaste. Con `go` se perdería el sitio, y con
      // cinco puertas de entrada eso se notaría cinco veces más.
      onPressed: () => context.push('/profile'),
    );
  }
}
