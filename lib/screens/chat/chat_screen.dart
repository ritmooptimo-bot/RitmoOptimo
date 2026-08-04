import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/skin_provider.dart';
import '../../providers/chat_provider.dart';
import '../../config/skins/skin_config.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await ref.read(chatProvider.notifier).load();
      _scrollToBottom();
    });
    // Polling (v1). Tiempo real con socket en una mejora posterior.
    _poll = Timer.periodic(const Duration(seconds: 8), (_) async {
      final before = ref.read(chatProvider).messages.length;
      await ref.read(chatProvider.notifier).load(silent: true);
      if (mounted && ref.read(chatProvider).messages.length != before) _scrollToBottom();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // Con la lista en reverse:true el "final del chat" es offset 0: el scroll
  // nace ya pegado a los últimos mensajes sin depender de maxScrollExtent
  // (que ListView.builder ESTIMA mientras construye → antes el animateTo se
  // quedaba a medio camino y aterrizabas en un mensaje del sábado).
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final t = _controller.text.trim();
    if (t.isEmpty) return;
    _controller.clear();
    final ok = await ref.read(chatProvider.notifier).send(t);
    if (!ok && mounted) {
      // El mensaje NO llegó: devolver el texto al campo para que no se pierda.
      _controller.text = t;
      _controller.selection = TextSelection.collapsed(offset: t.length);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se pudo enviar. Revisa tu conexión y vuelve a intentarlo.')));
    }
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final skin = ref.watch(activeSkinProvider);
    final chat = ref.watch(chatProvider);

    return Scaffold(
      backgroundColor: skin.background,
      appBar: AppBar(
        backgroundColor: skin.backgroundSecondary,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Tu equipo', style: TextStyle(color: skin.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
            Text('Ritmo Óptimo · estamos contigo', style: TextStyle(color: skin.textMuted, fontSize: 11)),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: (chat.loading && chat.messages.isEmpty)
                ? Center(child: CircularProgressIndicator(color: skin.accent))
                : chat.messages.isEmpty
                    ? _empty(skin)
                    : ListView.builder(
                        controller: _scroll,
                        // reverse: el chat SIEMPRE nace anclado a los últimos
                        // mensajes (patrón WhatsApp), entres cuando entres.
                        reverse: true,
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
                        itemCount: chat.messages.length,
                        itemBuilder: (_, i) {
                          // Con reverse, el índice 0 pinta ABAJO → mapear al
                          // orden cronológico real de la lista.
                          final idx = chat.messages.length - 1 - i;
                          final m = chat.messages[idx];
                          final anterior = idx > 0 ? chat.messages[idx - 1] : null;
                          // Separador de día cuando cambia la fecha (como WhatsApp)
                          final nuevoDia = anterior == null ||
                              !_mismoDia(anterior.timestamp, m.timestamp);
                          // Agrupar: mismo emisor y menos de 5 min → burbujas juntas
                          final agrupado = !nuevoDia &&
                              anterior.direction == m.direction &&
                              m.timestamp.difference(anterior.timestamp).inMinutes < 5;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (nuevoDia) _dateChip(skin, m.timestamp),
                              _bubble(skin, m, agrupado: agrupado),
                            ],
                          );
                        },
                      ),
          ),
          _inputBar(skin, chat.sending),
        ],
      ),
    );
  }

  Widget _empty(SkinConfig skin) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, color: skin.accent, size: 44),
            const SizedBox(height: 14),
            Text('Estamos aquí para ti',
                style: TextStyle(color: skin.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('Escríbenos cualquier duda sobre tu entrenamiento o tu plan. Te respondemos enseguida.',
                textAlign: TextAlign.center,
                style: TextStyle(color: skin.textMuted, fontSize: 13, height: 1.4)),
          ],
        ),
      ),
    );
  }

  // ── Fecha y hora: el chat no las mostraba y no se sabía cuándo llegó cada
  //    mensaje. Formato español, sin depender del idioma del sistema.
  static const _dias  = ['lunes','martes','miércoles','jueves','viernes','sábado','domingo'];
  static const _meses = ['enero','febrero','marzo','abril','mayo','junio','julio',
                         'agosto','septiembre','octubre','noviembre','diciembre'];

  bool _mismoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _etiquetaDia(DateTime t) {
    final ahora = DateTime.now();
    final hoy   = DateTime(ahora.year, ahora.month, ahora.day);
    final dia   = DateTime(t.year, t.month, t.day);
    final dif   = hoy.difference(dia).inDays;
    // SIEMPRE con día, mes y año: un "SÁBADO" a secas no dice QUÉ sábado
    // (petición del usuario tras perderse buscando un mensaje).
    final fecha = '${t.day} de ${_meses[t.month - 1]} de ${t.year}';
    if (dif == 0) return 'HOY · $fecha';
    if (dif == 1) return 'AYER · $fecha';
    return '${_dias[t.weekday - 1]}, $fecha';
  }

  String _hora(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// Chip centrado con el día, como en WhatsApp/Telegram.
  Widget _dateChip(SkinConfig skin, DateTime t) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: skin.backgroundSecondary,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: skin.border, width: 1),
          ),
          child: Text(
            _etiquetaDia(t),
            style: TextStyle(
              color: skin.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ),
    );
  }

  Widget _bubble(SkinConfig skin, ChatMessage m, {bool agrupado = false}) {
    final mine = m.isMine;
    final colorHora = mine
        ? skin.background.withValues(alpha: 0.75)
        : skin.textMuted;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        margin: EdgeInsets.only(top: agrupado ? 2 : 6, bottom: 2),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 7),
        decoration: BoxDecoration(
          color: mine ? skin.accent : skin.backgroundCard,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(mine ? 16 : (agrupado ? 6 : 16)),
            topRight: Radius.circular(mine ? (agrupado ? 6 : 16) : 16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
          border: mine ? null : Border.all(color: skin.border, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              m.text,
              style: TextStyle(
                color: mine ? skin.background : skin.textPrimary,
                fontSize: 14,
                height: 1.35,
              ),
            ),
            // Etiqueta de canal (hilo único): "vía WhatsApp" / "también por email…"
            if (m.channelTag != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  m.channelTag!,
                  style: TextStyle(
                    color: (mine ? skin.background : skin.textMuted).withValues(alpha: 0.7),
                    fontSize: 9.5,
                    fontStyle: FontStyle.italic,
                    height: 1,
                  ),
                ),
              ),
            const SizedBox(height: 3),
            // Hora abajo a la derecha, discreta (patrón WhatsApp/Telegram)
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _hora(m.timestamp),
                    style: TextStyle(color: colorHora, fontSize: 10.5, height: 1),
                  ),
                  if (mine) ...[
                    const SizedBox(width: 3),
                    Icon(Icons.done_all_rounded, size: 13, color: colorHora),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _inputBar(SkinConfig skin, bool sending) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          color: skin.backgroundSecondary,
          border: Border(top: BorderSide(color: skin.border, width: 1)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                style: TextStyle(color: skin.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Escribe a tu equipo…',
                  hintStyle: TextStyle(color: skin.textMuted, fontSize: 14),
                  filled: true,
                  fillColor: skin.background,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide(color: skin.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide(color: skin.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide(color: skin.accent),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Material(
              color: skin.accent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: sending ? null : _send,
                child: Padding(
                  padding: const EdgeInsets.all(11),
                  child: sending
                      ? SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: skin.background),
                        )
                      : Icon(Icons.send_rounded, color: skin.background, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
