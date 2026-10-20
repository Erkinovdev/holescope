import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:holescope/core/nav.dart';
import 'package:holescope/core/settings.dart';
import 'package:holescope/core/theme.dart';
import 'package:holescope/core/widgets.dart';
import 'package:holescope/features/car_mode.dart';
import 'package:holescope/features/comfort.dart';
import 'package:holescope/features/events_screens.dart';
import 'package:holescope/features/screens_live.dart';
import 'package:holescope/features/screens_data.dart';
import 'package:holescope/features/screens_more.dart';
import 'package:holescope/features/screens_new.dart';
import 'package:holescope/features/settings_v2.dart';
import 'package:holescope/features/welcome.dart';
import 'package:holescope/l10n/app_localizations.dart';
import 'package:holescope/services/config.dart';
import 'package:holescope/services/notify.dart';
import 'package:holescope/services/permissions.dart';
import 'package:holescope/services/providers.dart';
import 'package:holescope/voice/holi_voice.dart' show JustAudioHoliPlayer;
import 'package:holescope/voice/voice_check_screen.dart';
import 'package:holescope/voice/event_prompt_card.dart';


GoRouter buildRouter({String initial = '/splash'}) => GoRouter(
      navigatorKey: rootNavKey,
      initialLocation: initial,
      routes: [
        GoRoute(path: '/splash', builder: (_, __) => const WelcomeSplash()),
        GoRoute(path: '/onboarding/lang', builder: (_, __) => const LanguageStep()),
        GoRoute(path: '/onboarding/intro', builder: (_, __) => const IntroStep()),
        GoRoute(path: '/onboarding/location', builder: (_, __) => const PermissionStep(location: true)),
        GoRoute(path: '/onboarding/motion', builder: (_, __) => const PermissionStep(location: false)),
        GoRoute(path: '/onboarding/mount', builder: (_, __) => const MountStep()),
        GoRoute(path: '/onboarding/role', builder: (_, __) => const RoleStep()),
        GoRoute(path: '/onboarding/theme', builder: (_, __) => const ThemeStep()),
        GoRoute(path: '/onboarding/ready', builder: (_, __) => const ReadyStep()),
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
        GoRoute(path: '/pothole/:id', builder: (_, s) => PotholeScreen(id: int.tryParse(s.pathParameters['id']!) ?? 0)),
        GoRoute(path: '/warning', builder: (_, __) => const WarningScreen()),
        GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
        GoRoute(path: '/settings/notifications', builder: (_, __) => const NotificationSettings()),
        GoRoute(path: '/settings/voice', builder: (_, __) => const VoiceSettings()),
        GoRoute(path: '/settings/events', builder: (_, __) => const EventSettings()),
        GoRoute(path: '/settings/warnings', builder: (_, __) => const WarningSettings()),
        GoRoute(path: '/settings/recording', builder: (_, __) => const RecordingSettings()),
        GoRoute(path: '/settings/look', builder: (_, __) => const LookSettings()),
        GoRoute(path: '/settings/language', builder: (_, __) => const LanguageSettings()),
        GoRoute(path: '/settings/privacy', builder: (_, __) => const PrivacySettings()),
        GoRoute(path: '/settings/car', builder: (_, __) => const CarSettings()),
        GoRoute(path: '/settings/about', builder: (_, __) => const AboutScreen()),
        GoRoute(path: '/voice-check', builder: (_, __) => const VoiceCheckScreen()),
        GoRoute(path: '/complaint/:cid', builder: (_, s) => ComplaintScreen(clusterId: int.tryParse(s.pathParameters['cid']!) ?? 0)),
        GoRoute(path: '/complaint/status/:id', builder: (_, s) => ComplaintStatusScreen(id: int.tryParse(s.pathParameters['id']!) ?? 0)),
        GoRoute(path: '/route', builder: (_, __) => const RouteChoiceScreen()),
        GoRoute(path: '/notifications', builder: (_, __) => const NotificationCenter()),
        GoRoute(path: '/car', builder: (_, __) => const CarScreen()),
        GoRoute(path: '/queue', builder: (_, __) => const QueueScreen()),
        GoRoute(path: '/strong-hit', builder: (_, s) => StrongHitScreen(peak: double.tryParse(s.uri.queryParameters['peak'] ?? '') ?? 0, speedKmh: double.tryParse(s.uri.queryParameters['v'] ?? '') ?? 0)),
        GoRoute(path: '/suspension', builder: (_, __) => const SuspensionScreen()),
        GoRoute(path: '/commands', builder: (_, __) => const HoliCommandsScreen()),
        GoRoute(path: '/types', builder: (_, __) => const EventTypesScreen()),
        GoRoute(path: '/city', builder: (_, __) => const CityDashboardScreen()),
        GoRoute(path: '/challenges', builder: (_, __) => const ChallengesScreen()),
        GoRoute(path: '/weekly', builder: (_, __) => const WeeklyReportScreen()),
        GoRoute(path: '/vehicle', builder: (_, __) => const VehicleScreen()),
        GoRoute(path: '/question', builder: (_, __) => const QuestionScreen()),
        GoRoute(path: '/trip-summary', builder: (_, __) => const TripSummaryScreen()),
        GoRoute(path: '/mount', builder: (_, __) => const MountStep(onboarding: false)),
        GoRoute(path: '/role', builder: (_, __) => const RoleStep(onboarding: false)),
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (kIsWeb) {
        final uz = ref.read(settingsProvider).locale?.languageCode == 'uz';
        ref.read(bannerProvider.notifier).show(NoteBanner('service', uz ? 'Veb-versiya (sinov uchun)' : 'Веб-версия для проверки', uz ? 'Fonda yozuv va bildirishnomalar ishlamaydi.' : 'Запись в фоне и системные уведомления в браузере недоступны.'));
      }
      final s = ref.read(settingsProvider);
      unawaited(postWeeklyDigest(ref.read(notificationHubProvider), ref.read(dbProvider), s, DateTime.now(), uz: s.locale?.languageCode == 'uz'));
    });
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
    JustAudioHoliPlayer.volume = s.holiVolume;
    ref.listen(permStateProvider, (_, __) => _syncEngine());
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncEngine());
    // предупреждение о яме впереди → экран HUD; пропала (проехали) → закрываем
    ref.listen(warningProvider, (prev, next) {
      final onHud = router.routerDelegate.currentConfiguration.uri.path == '/warning';
      // на мониторе предупреждение показывает сам экран автомонитора
      if (next != null && prev == null && !onHud && !AppConfig.carMonitor) {
        router.push('/warning');
      } else if (next == null && prev != null && onHud) {
        router.pop();
      }
    });
    return MaterialApp.router(
      onGenerateTitle: (c) => AppLocalizations.of(c).appName,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: TextScaler.linear(mq.textScaler.scale(1) * s.textScale)),
          child: Stack(children: [child ?? const SizedBox.shrink(), const EventPromptOverlay()]),
        );
      },
      themeMode: AppConfig.carMonitor && s.carNight ? ThemeMode.dark : s.themeMode,
      theme: buildTheme(Brightness.light, highContrast: s.highContrast),
      darkTheme: buildTheme(Brightness.dark, highContrast: s.highContrast),
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
