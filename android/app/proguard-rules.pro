# ── flutter_local_notifications en release (R8/ProGuard) ──────────────────────
# El plugin persiste las notificaciones programadas con Gson. En release, R8
# borra las firmas genéricas y Gson revienta al RELEERLAS (p.ej. al reprogramar
# tras actualizar la app -MY_PACKAGE_REPLACED- o reiniciar el móvil -BOOT_COMPLETED-):
#   java.lang.IllegalStateException: TypeToken must be created with a type
#   argument: new TypeToken<...>() {}; When using code shrinkers (ProGuard, R8,
#   ...) make sure that generic signatures are preserved.
# → El ScheduledNotificationBootReceiver crasheaba y la app "no cargaba" tras
#   actualizar. Preservamos el plugin + las firmas genéricas + los TypeToken.
-keep class com.dexterous.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes InnerClasses,EnclosingMethod
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep public class * implements java.lang.reflect.Type
-dontwarn com.google.gson.**
