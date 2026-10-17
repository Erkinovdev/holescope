import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:holescope/core/settings.dart';
import 'package:holescope/core/theme.dart';
import 'package:holescope/core/widgets.dart';
import 'package:holescope/features/screens_live.dart';
import 'package:holescope/features/screens_main.dart';
import 'package:holescope/features/screens_more.dart';
import 'package:holescope/features/screens_new.dart';
import 'package:holescope/features/splash.dart';
import 'package:holescope/l10n/app_localizations.dart';
import 'package:holescope/services/permissions.dart';
import 'package:holescope/services/providers.dart';

final _root = GlobalKey<NavigatorState>();

GoRouter buildRouter({String initial = '/splash'}) => GoRouter(
      navigatorKey: _root,
      initialLocation: initial,
      routes: [
        GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
        GoRoute(path: '/onboarding/role', builder: (_, __) => const RoleScreen(onboarding: true)),
        GoRoute(path: '/onboarding/mount', builder: (_, __) => const MountScreen(onboarding: true)),
        GoRoute(path: '/permissions', builder: (_, __) => const PermissionsScreen()),
        StatefulShellRoute.indexedStack(
          builder: (_, __, shell) => HpShell(shell: shell),
          branches: [
            StatefulShellBranch(routes: [GoRoute(path: '/map', builder: (_, __) => const LiveMapScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: '/drive', builder: (_, __) => const DriveScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: '/streets', builder: (_, __) => const StreetsScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen())]),
          ],
        ),
        GoRoute(path: '/trips', builder: (_, __) => const TripsScreen()),
        GoRoute(path: '/my-map', builder: (_, __) => const MyMapScreen()),
        GoRoute(path: '/pothole/:id', builder: (_, s) => PotholeScreen(id: s.pathParameters['id']!)),
        GoRoute(path: '/warning', builder: (_, __) => const WarningScreen()),
        GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
        GoRoute(path: '/complaint', builder: (_, __) => const ComplaintScreen()),
        GoRoute(path: '/complaint/status', builder: (_, __) => const ComplaintStatusScreen()),
        GoRoute(path: '/route', builder: (_, __) => const RouteChoiceScreen()),
        GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen()),
        GoRoute(path: '/city', builder: (_, __) => const CityDashboardScreen()),
        GoRoute(path: '/challenges', builder: (_, __) => const ChallengesScreen()),
        GoRoute(path: '/weekly', builder: (_, __) => const WeeklyReportScreen()),
        GoRoute(path: '/vehicle', builder: (_, __) => const VehicleScreen()),
        GoRoute(path: '/question', builder: (_, __) => const QuestionScreen()),
        GoRoute(path: '/trip-summary', builder: (_, __) => const TripSummaryScreen()),
        GoRoute(path: '/mount', builder: (_, __) => const MountScreen()),
        GoRoute(path: '/role', builder: (_, __) => const RoleScreen()),
      ],
    );

class HoleScopeApp extends ConsumerStatefulWidget {
  const HoleScopeApp({super.key, this.initialLocation = '/splash'});
  final String initialLocation;
  @override
  ConsumerState<HoleScopeApp> createState() => _HoleScopeAppState();
}

class _HoleScopeAppState extends ConsumerState<HoleScopeApp> with WidgetsBindingObserver {
  late final GoRouter router = buildRouter(initial: widget.initialLocation);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // вернулись из системных настроек — перечитываем разрешения
    if (state == AppLifecycleState.resumed) ref.invalidate(permStateProvider);
  }

  /// Автозапись включена, онбординг пройден и есть геолокация → движок работает в фоне.
  void _syncEngine() {
    final s = ref.read(settingsProvider);
    final perm = ref.read(permStateProvider).value ?? const PermState();
    final eng = ref.read(engineProvider);
    final want = s.onboarded && s.autoRecord && perm.canRecord;
    if (want && !eng.running) {
      eng.start();
    } else if (!want && eng.running) {
      eng.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    ref.listen(settingsProvider.select((x) => (x.onboarded, x.autoRecord)), (_, __) => _syncEngine());
    ref.listen(permStateProvider, (_, __) => _syncEngine());
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncEngine());
    // предупреждение о яме впереди → экран HUD; пропала (проехали) → закрываем
    ref.listen(warningProvider, (prev, next) {
      final onHud = router.routerDelegate.currentConfiguration.uri.path == '/warning';
      if (next != null && prev == null && !onHud) {
        router.push('/warning');
      } else if (next == null && prev != null && onHud) {
        router.pop();
      }
    });
    return MaterialApp.router(
      onGenerateTitle: (c) => AppLocalizations.of(c).appName,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      themeMode: s.themeMode,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      locale: s.locale, // null → язык системы
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      localeResolutionCallback: (loc, supported) {
        for (final x in supported) {
          if (x.languageCode == loc?.languageCode) return x;
        }
        return const Locale('ru'); // по умолчанию русский
      },
    );
  }
}
