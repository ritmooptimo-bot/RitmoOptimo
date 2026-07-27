import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';

// ── Notificaciones locales ────────────────────────────────────────────────
// Recordatorio DIARIO local del check-in de Bienestar. Todo en el dispositivo:
// sin FCM, sin backend, sin agente (0 tokens). El deportista concede el permiso
// una vez; al pulsar la notificación se abre la pestaña Bienestar.
class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static const int _dailyCheckinId = 1001;

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
        if (resp.payload == 'checkin') onCheckinTap?.call();
      },
    );
  }

  // Pide el permiso de notificaciones (Android 13+). Devuelve true si concedido.
  static Future<bool> requestPermission() async {
    final impl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final granted = await impl?.requestNotificationsPermission();
    return granted ?? true;
  }

  // Programa (o re-programa) el recordatorio diario a las [hour]:[minute].
  static Future<void> scheduleDailyCheckin({int hour = 8, int minute = 0}) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'checkin_diario',
        'Check-in de bienestar',
        channelDescription: 'Recordatorio diario para tu check-in de bienestar',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    try {
      await _plugin.zonedSchedule(
        _dailyCheckinId,
        'Buenos días ☀️',
        'Haz tu check-in de bienestar antes de entrenar (2 min).',
        _nextInstanceOf(hour, minute),
        details,
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
        'Buenos días ☀️',
        'Haz tu check-in de bienestar antes de entrenar (2 min).',
        _nextInstanceOf(hour, minute),
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: 'checkin',
      );
    }
  }

  static Future<void> cancelDaily() => _plugin.cancel(_dailyCheckinId);

  static tz.TZDateTime _nextInstanceOf(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
