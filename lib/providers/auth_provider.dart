import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/app_auth_client.dart';
import 'workout_provider.dart';
import 'history_provider.dart';
import 'plan_calendar_provider.dart';
import 'chat_provider.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  final AuthStatus status;
  final String? error;

  const AuthState({required this.status, this.error});

  bool get isAuthenticated => status == AuthStatus.authenticated;
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AppAuthClient _auth;
  final Ref _ref;

  AuthNotifier(this._auth, this._ref) : super(const AuthState(status: AuthStatus.unknown)) {
    _checkExistingSession();
  }

  /// Tira TODO lo que quedó en memoria del atleta anterior.
  ///
  /// El logout solo borraba el token: el panel, el historial, el calendario, la
  /// sesión activa y —sobre todo— el CHAT seguían cargados. Dos atletas que
  /// compartan móvil veían los datos y los mensajes privados del otro hasta que
  /// cada pantalla recargase por su cuenta.
  void _wipeAthleteData() {
    _ref.invalidate(dashboardProvider);
    _ref.invalidate(activeSessionProvider);
    _ref.invalidate(historyProvider);
    _ref.invalidate(planCalendarProvider);
    _ref.invalidate(chatProvider);
  }

  Future<void> _checkExistingSession() async {
    final has = await _auth.hasValidSession();
    state = AuthState(status: has ? AuthStatus.authenticated : AuthStatus.unauthenticated);
  }

  /// Login con email + contraseña + device_id (validado en servidor)
  Future<void> login(String email, String password) async {
    try {
      await _auth.loginWithDevice(email: email, password: password);
      state = const AuthState(status: AuthStatus.authenticated);
    } catch (e) {
      final raw = e.toString();
      // Sin red decía "Email o contraseña incorrectos" — mensaje engañoso que
      // hace dudar al usuario de su contraseña cuando el problema es la conexión.
      final esRed = raw.contains('SocketException') ||
          raw.contains('connection') || raw.contains('Connection') ||
          raw.contains('timeout') || raw.contains('Network');
      final msg = raw.contains('no está autorizado')
          ? 'Este dispositivo no está autorizado.\nEscanea el QR de activación.'
          : esRed
              ? 'Sin conexión. Comprueba tu internet e inténtalo de nuevo.'
              : 'Email o contraseña incorrectos.';
      state = AuthState(status: AuthStatus.unauthenticated, error: msg);
    }
  }

  /// Llamado desde PairingScreen tras vincular con éxito
  Future<void> onDevicePaired() async {
    state = const AuthState(status: AuthStatus.authenticated);
  }

  Future<void> logout() async {
    await _auth.clearSession();
    _wipeAthleteData();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  /// La sesión se ha perdido sola (401 + refresco fallido).
  ///
  /// Antes solo se navegaba a login, pero el estado seguía diciendo
  /// "autenticado" → el router rebotaba de vuelta a Inicio al instante y la app
  /// quedaba en bucle de 401 sin forma de volver a entrar salvo matándola.
  void sessionLost() {
    _wipeAthleteData();
    state = const AuthState(
      status: AuthStatus.unauthenticated,
      error: 'Tu sesión ha caducado. Entra de nuevo.',
    );
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(ref.read(appAuthClientProvider), ref),
);
