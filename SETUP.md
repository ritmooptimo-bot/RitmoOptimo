# RitmoOptimo Mobile — Setup Inicial

## 1. Instalar Flutter SDK (si no está instalado)

```
winget install Google.Flutter
```
O descargar desde https://docs.flutter.dev/get-started/install/windows

Cerrar y reabrir PowerShell, luego verificar:
```
flutter doctor
```

## 2. Generar archivos nativos (Android + iOS)

Ejecutar DENTRO de esta carpeta (`ritmooptimo_mobile/`):

```
flutter create . --org com.antigravity --project-name ritmooptimo_mobile
```

Esto añade `android/`, `ios/`, `linux/`, `web/` sin tocar el código Dart existente.

## 3. Instalar dependencias

```
flutter pub get
```

## 4. Añadir fuentes (assets/fonts/)

Copiar a `assets/fonts/`:
- Inter-Regular.ttf, Inter-Medium.ttf, Inter-SemiBold.ttf, Inter-Bold.ttf
  → Descargar: https://fonts.google.com/specimen/Inter
- RobotoMono-Regular.ttf, RobotoMono-Medium.ttf
  → Descargar: https://fonts.google.com/specimen/Roboto+Mono
- Formula1-Regular.otf, Formula1-Bold.otf
  → Fuente oficial F1 (licencia comercial) o usar Rajdhani como alternativa:
    https://fonts.google.com/specimen/Rajdhani

Crear las carpetas si no existen:
```
mkdir assets\fonts
mkdir assets\images
mkdir assets\icons
```

## 5. Permisos Android (android/app/src/main/AndroidManifest.xml)

Añadir dentro de `<manifest>`:
```xml
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.INTERNET" />
```

## 6. Permisos iOS (ios/Runner/Info.plist)

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>RitmoOptimo necesita Bluetooth para conectar sensores de FC</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>RitmoOptimo necesita tu ubicación para registrar el track GPS</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>RitmoOptimo necesita tu ubicación en segundo plano para tracks GPS</string>
<key>UIBackgroundModes</key>
<array>
  <string>bluetooth-central</string>
  <string>location</string>
</array>
```

## 7. Ejecutar

```
flutter run
```

## Estructura del proyecto

```
lib/
├── main.dart                    ← Entry point + ProviderScope
├── config/
│   ├── router.dart              ← GoRouter + ShellRoute (bottom nav)
│   └── skins/
│       ├── skin_config.dart     ← Token system (colores, tipografía, radios)
│       ├── dark_light_skin.dart ← Skin 1: Oscuro + Día
│       └── f1_skin.dart         ← Skin 2: F1 Cockpit
├── core/
│   ├── channels/
│   │   └── native_channels.dart ← BLE + GPS Platform Channels
│   └── network/
│       └── api_client.dart      ← Dio + JWT interceptor + todos los endpoints
├── providers/
│   ├── skin_provider.dart       ← Estado del skin (persistido en SharedPreferences)
│   ├── auth_provider.dart       ← Auth: login/logout/token check
│   └── workout_provider.dart    ← Dashboard + ActiveSession state
└── screens/
    ├── auth/login_screen.dart
    ├── home/home_screen.dart    ← Dashboard: CTL/ATL/TSB + sesión hoy + wellness
    ├── session/
    │   ├── session_screen.dart         ← Timer + FC en tiempo real
    │   └── session_complete_screen.dart ← RPE + distancia + sensaciones
    ├── plan/week_plan_screen.dart      ← Semana completa
    ├── wellness/wellness_screen.dart   ← Check-in diario + HRV
    └── profile/profile_screen.dart    ← Selector de skins + logout
```

## Backend ya listo (migración 041 aplicada)

Endpoints disponibles en `/api/training-plan`:
- GET  /athlete/dashboard    → Home screen (1 call)
- GET  /athlete/week         → Plan semanal
- GET  /athlete/today        → Sesión de hoy
- POST /sessions/:id/start   → Iniciar sesión
- POST /sessions/:id/complete → Completar con datos reales
- POST /hrv                  → HRV matutino
- GET  /hrv                  → Historial HRV
- POST /hr-recovery          → Test recuperación cardíaca
- POST /sessions/:id/gps-track → Track GPS
- GET  /athlete/thresholds   → FTP/LTHR/pace activos
