import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Modelo de mensaje ─────────────────────────────────────────────
class ChatMessage {
  final String id;
  final String direction; // 'inbound' = cliente | 'outbound' = equipo
  final String text;
  final bool sentByAi;
  final List<String> channels; // canales por los que fue/vino (hilo único)
  final DateTime timestamp;

  const ChatMessage({
    required this.id,
    required this.direction,
    required this.text,
    required this.sentByAi,
    this.channels = const ['app'],
    required this.timestamp,
  });

  bool get isMine => direction == 'inbound';

  static const _names = {
    'whatsapp': 'WhatsApp', 'telegram': 'Telegram', 'email': 'email', 'app': 'app',
  };

  // Etiqueta de canal para el hilo único (null = mensaje normal de la app).
  // Mensaje del atleta por un canal externo → "vía WhatsApp".
  // Respuesta del equipo difundida a canales externos → "también por WhatsApp, email".
  String? get channelTag {
    final others = channels.where((c) => c != 'app').map((c) => _names[c] ?? c).toList();
    if (others.isEmpty) return null;
    return isMine ? 'vía ${others.first}' : 'también por ${others.join(', ')}';
  }

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'].toString(),
        direction: (j['direction'] as String?) ?? 'outbound',
        text: (j['message_text'] as String?) ?? '',
        sentByAi: j['sent_by_ai'] == true,
        channels: (j['channels'] is List)
            ? (j['channels'] as List).map((e) => e.toString()).toList()
            : [ (j['channel'] as String?) ?? 'app' ],
        timestamp: DateTime.tryParse(j['timestamp']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
      );
}

// ── Estado ────────────────────────────────────────────────────────
class ChatState {
  final List<ChatMessage> messages;
  final bool loading;
  final bool sending;
  final String? error;
  /// Respuestas del entrenador que aún no ha visto. Sin esto, si el entrenador
  /// contestaba el atleta no se enteraba hasta que entrase por curiosidad.
  final int unread;

  const ChatState({
    this.messages = const [],
    this.loading = false,
    this.sending = false,
    this.error,
    this.unread = 0,
  });

  ChatState copyWith({List<ChatMessage>? messages, bool? loading, bool? sending,
                      String? error, int? unread}) =>
      ChatState(
        messages: messages ?? this.messages,
        loading: loading ?? this.loading,
        sending: sending ?? this.sending,
        error: error,
        unread: unread ?? this.unread,
      );
}

// ── Notifier ──────────────────────────────────────────────────────
class ChatNotifier extends StateNotifier<ChatState> {
  ChatNotifier() : super(const ChatState()) {
    _dio = Dio(BaseOptions(
      baseUrl: 'https://ritmooptimo.tech/api/app/chat',
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
    ));
    _dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) async {
      final token = await _storage.read(key: 'ro_access_token');
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
      handler.next(options);
    }));
  }

  late final Dio _dio;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  List<ChatMessage> _parse(dynamic data) {
    final raw = (data is Map && data['messages'] is List) ? data['messages'] as List : const [];
    return raw.map((e) => ChatMessage.fromJson(e as Map<String, dynamic>)).toList();
  }

  static const _kUltimaLectura = 'chat_ultima_lectura';

  Future<void> load({bool silent = false}) async {
    if (!silent) state = state.copyWith(loading: true, error: null);
    try {
      final r = await _dio.get('/messages');
      final msgs = _parse(r.data);
      state = state.copyWith(messages: msgs, loading: false, error: null,
                             unread: await _contarNoLeidos(msgs));
    } catch (_) {
      state = state.copyWith(loading: false, error: silent ? state.error : 'No se pudo cargar el chat');
    }
  }

  /// Respuestas del entrenador posteriores a la última vez que abrió el chat.
  /// Se resuelve en el móvil comparando marcas de tiempo: no hace falta que el
  /// servidor lleve la cuenta de lecturas.
  Future<int> _contarNoLeidos(List<ChatMessage> msgs) async {
    try {
      final p = await SharedPreferences.getInstance();
      final iso = p.getString(_kUltimaLectura);
      final desde = iso != null ? DateTime.tryParse(iso) : null;
      if (desde == null) {
        // Primera vez: no se marca todo como no leído (sería un globo enorme
        // por mensajes viejos que ya vio por WhatsApp). Solo lo de hoy.
        final hoy = DateTime.now().subtract(const Duration(hours: 12));
        return msgs.where((m) => !m.isMine && m.timestamp.isAfter(hoy)).length;
      }
      return msgs.where((m) => !m.isMine && m.timestamp.isAfter(desde)).length;
    } catch (_) {
      return 0;
    }
  }

  /// Al abrir el chat: se da por leído todo lo que hay.
  Future<void> marcarLeido() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kUltimaLectura, DateTime.now().toIso8601String());
    } catch (_) {}
    if (state.unread != 0) state = state.copyWith(unread: 0);
  }

  /// Comprobación de fondo para el globo, sin tocar el estado de carga.
  Future<void> refrescarNoLeidos() => load(silent: true);

  /// Envía el mensaje. Devuelve false si NO llegó al servidor: en ese caso el
  /// mensaje optimista se retira de la lista (antes se quedaba pintado y el
  /// siguiente polling lo hacía desaparecer EN SILENCIO — un "me duele la
  /// rodilla" perdido sin que nadie lo supiera). La pantalla restaura el texto.
  Future<bool> send(String text) async {
    final t = text.trim();
    if (t.isEmpty) return true;

    // Mensaje optimista mientras responde el servidor
    final temp = ChatMessage(
      id: 'tmp_${DateTime.now().millisecondsSinceEpoch}',
      direction: 'inbound',
      text: t,
      sentByAi: false,
      timestamp: DateTime.now(),
    );
    state = state.copyWith(messages: [...state.messages, temp], sending: true);

    try {
      await _dio.post('/messages', data: {'text': t});
      // Recargar: trae el mensaje guardado + la respuesta del equipo (agente)
      await load(silent: true);
      state = state.copyWith(sending: false);
      return true;
    } catch (_) {
      // Quitar el mensaje que NO llegó (no fingir que se envió)
      state = state.copyWith(
        messages: state.messages.where((m) => m.id != temp.id).toList(),
        sending: false,
        error: 'No se pudo enviar el mensaje',
      );
      return false;
    }
  }
}

final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>((_) => ChatNotifier());
