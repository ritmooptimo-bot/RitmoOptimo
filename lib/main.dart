import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:app_links/app_links.dart';
import 'config/router.dart';
import 'providers/skin_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  runApp(const ProviderScope(child: RitmoOptimoApp()));
}

class RitmoOptimoApp extends ConsumerStatefulWidget {
  const RitmoOptimoApp({super.key});

  @override
  ConsumerState<RitmoOptimoApp> createState() => _RitmoOptimoAppState();
}

class _RitmoOptimoAppState extends ConsumerState<RitmoOptimoApp> {
  late final AppLinks _appLinks;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  void _initDeepLinks() {
    _appLinks = AppLinks();

    // Esperar al primer frame para que GoRouter esté montado
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _appLinks.getInitialLink().then((uri) {
        if (uri != null) _handleDeepLink(uri);
      });
    });

    // Deep links mientras la app está en segundo plano o activa
    _appLinks.uriLinkStream.listen(_handleDeepLink);
  }

  void _handleDeepLink(Uri uri) {
    final router = ref.read(routerProvider);

    // ritmooptimo://pair?token=XXX
    if (uri.scheme == 'ritmooptimo' && uri.host == 'pair') {
      final token = uri.queryParameters['token'] ?? '';
      if (token.isNotEmpty) {
        router.go('/pair?token=$token');
      }
      return;
    }

    // https://ritmooptimo.tech/app/activar?token=XXX
    if (uri.host == 'ritmooptimo.tech' && uri.path == '/app/activar') {
      final token = uri.queryParameters['token'] ?? '';
      if (token.isNotEmpty) {
        router.go('/pair?token=$token');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final skinState = ref.watch(skinProvider);
    final router    = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Ritmo Óptimo',
      debugShowCheckedModeBanner: false,
      theme: skinState.skin.toTheme(),
      routerConfig: router,
    );
  }
}
