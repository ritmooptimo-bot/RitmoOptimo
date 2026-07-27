import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';

// ── Notificaciones locales ────────────────────────────────────────────────
// Recordatorio DIARIO local del check-in de Bienestar. Todo en el dispositivo:
// sin FCM, sin backend, sin agente (0 tokens). El deportista concede el permiso
// una vez; al pulsar la notificación se abre la pestaña Bienestar.
//
// La notificación es FIJA (ongoing): salta a las 08:00 y no se puede descartar
// deslizando. Solo desaparece cuando el deportista:
//   1) hace el check-in  → la app llama a completedToday() y la retira, o
//   2) pulsa "Hoy no"    → acción de la propia notificación que la quita SOLO
//                          por hoy (cancelNotification). El recordatorio diario
//                          vuelve a mostrarse mañana (por si cambia de idea o ya
//                          tiene la banda). Así el dato se vive como una
//                          necesidad real para ajustar el plan, con salida digna.

// Handler en segundo plano de las acciones de la notificación. La acción "Hoy no"
// ya lleva cancelNotification:true → el SO retira la notificación de hoy sin abrir
// la app; el recordatorio diario la vuelve a mostrar mañana. No hace falta más.
@pragma('vm:entry-point')
void notificationActionBackground(NotificationResponse resp) {
  // no-op intencionado (ver arriba).
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static const int _dailyCheckinId = 1001;
  static int _schedHour = 8;
  static int _schedMinute = 0;

  // La app (main/router) setea este callback para navegar a Bienestar al pulsar.
  static void Function()? onCheckinTap;

  static Future<void> init() async {
    tzdata.initializeTimeZones();
    try {
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      // Si falla, se queda en UTC (peor pero no rompe).
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (resp) {
        // "Hoy no" solo retira la notificación de hoy; NO navegamos.
        if (resp.actionId == 'skip_today') return;
        if (resp.payload == 'checkin') onCheckinTap?.call();
      },
      onDidReceiveBackgroundNotificationResponse: notificationActionBackground,
    );
  }

  // Pide el permiso de notificaciones (Android 13+). Devuelve true si concedido.
  static Future<bool> requestPermission() async {
    final impl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final granted = await impl?.requestNotificationsPermission();
    return granted ?? true;
  }

  // Detalles de la notificación fija + acción "Hoy no" + copy que vende el valor.
  static NotificationDetails _details() {
    const body =
        'Haz tu check-in: tu entrenador ajusta la sesión de hoy a cómo estás. '
        'Sin este dato, el plan va a ciegas. Son 2 minutos.';
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        'checkin_diario',
        'Check-in de bienestar',
        channelDescription: 'Recordatorio diario para tu check-in de bienestar',
        importance: Importance.high,
        priority: Priority.high,
        ongoing: true, // fija: no se descarta deslizando
        autoCancel: false, // ni al tocarla (se retira al completar el check-in)
        onlyAlertOnce: true, // no re-vibra cuando se re-muestra cada día
        styleInformation: BigTextStyleInformation(body),
        actions: <AndroidNotificationAction>[
          AndroidNotificationAction(
            'skip_today',
            'Hoy no',
            cancelNotification: true, // la retira hoy; vuelve mañana
            showsUserInterface: false,
          ),
        ],
      ),
    );
  }

  // Programa (o re-programa) el recordatorio diario a las [hour]:[minute].
  // skipToday=true fuerza que la primera aparición sea mañana (ya hecho hoy).
  static Future<void> scheduleDailyCheckin(
      {int hour = 8, int minute = 0, bool skipToday = false}) async {
    _schedHour = hour;
    _schedMinute = minute;
    final when = _nextInstanceOf(hour, minute, skipToday: skipToday);
    try {
      await _plugin.zonedSchedule(
        _dailyCheckinId,
        'Tu plan te necesita 2 min ☀️',
        'Haz tu check-in para que tu entrenador ajuste la sesión de hoy.',
        when,
        _details(),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time, // se repite cada día
        payload: 'checkin',
      );
    } catch (_) {
      // Si el SO bloquea las alarmas exactas, cae a inexacta (suficiente para
      // un recordatorio matutino).
      await _plugin.zonedSchedule(
        _dailyCheckinId,
        'Tu plan te necesita 2 min ☀️',
        'Haz tu check-in para que tu entrenador ajuste la sesión de hoy.',
        when,
        _details(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: 'checkin',
      );
    }
  }

  // El check-in de HOY ya está hecho (por la app o por otro canal): retira la
  // notificación fija y re-arma el recordatorio para mañana.
  static Future<void> completedToday() async {
    await _plugin.cancel(_dailyCheckinId);
    await scheduleDailyCheckin(
        hour: _schedHour, minute: _schedMinute, skipToday: true);
  }

  static Future<void> cancelDaily() => _plugin.cancel(_dailyCheckinId);

  static tz.TZDateTime _nextInstanceOf(int hour, int minute,
      {bool skipToday = false}) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (skipToday || scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
