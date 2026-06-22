import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/app_auth_client.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  final AuthStatus status;
  final String? error;

  const AuthState({required this.status, this.error});

  bool get isAuthenticated => status == AuthStatus.authenticated;
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AppAuthClient _auth;

  AuthNotifier(this._auth) : super(const AuthState(status: AuthStatus.unknown)) {
    _checkExistingSession();
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
      final msg = raw.contains('no está autorizado')
          ? 'Este dispositivo no está autorizado.\nEscanea el QR de activación.'
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
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(ref.read(appAuthClientProvider)),
);
