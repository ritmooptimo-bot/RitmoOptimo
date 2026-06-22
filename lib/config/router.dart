import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../screens/home/home_screen.dart';
import '../screens/session/session_screen.dart';
import '../screens/session/session_complete_screen.dart';
import '../screens/plan/week_plan_screen.dart';
import '../screens/wellness/wellness_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/pairing_screen.dart';

// ── Routes ────────────────────────────────────────────────────────
abstract class AppRoutes {
  static const login           = '/login';
  static const home            = '/';
  static const weekPlan        = '/plan';
  static const session         = '/session/:id';
  static const sessionComplete = '/session/:id/complete';
  static const wellness        = '/wellness';
  static const profile         = '/profile';
  static const pair            = '/pair';   // ritmooptimo://pair?token=XXX
}

// ── Router ────────────────────────────────────────────────────────
final _rootNavigatorKey  = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: AppRoutes.home,
    redirect: (context, state) {
      final isAuth    = authState.isAuthenticated;
      final isUnknown = authState.status == AuthStatus.unknown;
      final loc       = state.matchedLocation;

      if (isUnknown)                              return null;
      if (loc == AppRoutes.pair)                  return null; // siempre accesible
      if (!isAuth && loc != AppRoutes.login)      return AppRoutes.login;
      if (isAuth  && loc == AppRoutes.login)      return AppRoutes.home;
      return null;
    },
    routes: [
      // ── Auth ─────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.login,
        builder: (_, __) => const LoginScreen(),
      ),

      // ── Device Pairing (deep link) ───────────────────────────
      GoRoute(
        path: AppRoutes.pair,
        builder: (_, state) {
          final token = state.uri.queryParameters['token'] ?? '';
          return PairingScreen(token: token);
        },
      ),

      // ── Shell con Bottom Navigation ──────────────────────────
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) => _AppShell(child: child),
        routes: [
          GoRoute(
            path: AppRoutes.home,
            builder: (_, __) => const HomeScreen(),
          ),
          GoRoute(
            path: AppRoutes.weekPlan,
            builder: (_, __) => const WeekPlanScreen(),
          ),
          GoRoute(
            path: AppRoutes.wellness,
            builder: (_, __) => const WellnessScreen(),
          ),
          GoRoute(
            path: AppRoutes.profile,
            builder: (_, __) => const ProfileScreen(),
          ),
        ],
      ),

      // ── Session (full screen) ────────────────────────────────
      GoRoute(
        path: AppRoutes.session,
        builder: (_, state) => SessionScreen(
          sessionId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: AppRoutes.sessionComplete,
        builder: (_, state) => SessionCompleteScreen(
          sessionId: state.pathParameters['id']!,
        ),
      ),
    ],
  );
});

// ── Bottom Nav Shell ─────────────────────────────────────────────
class _AppShell extends ConsumerWidget {
  final Widget child;
  const _AppShell({required this.child});

  int _currentIndex(BuildContext context) {
    final loc = GoRouterState.of(context).matchedLocation;
    if (loc == AppRoutes.weekPlan) return 1;
    if (loc == AppRoutes.wellness) return 2;
    if (loc == AppRoutes.profile)  return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idx = _currentIndex(context);
    return Scaffold(
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: idx,
        type: BottomNavigationBarType.fixed,
        onTap: (i) {
          switch (i) {
            case 0: context.go(AppRoutes.home);
            case 1: context.go(AppRoutes.weekPlan);
            case 2: context.go(AppRoutes.wellness);
            case 3: context.go(AppRoutes.profile);
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined),      activeIcon: Icon(Icons.home),           label: 'Inicio'),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_today_outlined), activeIcon: Icon(Icons.calendar_today), label: 'Plan'),
          BottomNavigationBarItem(icon: Icon(Icons.favorite_outline),   activeIcon: Icon(Icons.favorite),       label: 'Bienestar'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline),     activeIcon: Icon(Icons.person),         label: 'Perfil'),
        ],
      ),
    );
  }
}
