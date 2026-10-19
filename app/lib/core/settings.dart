import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum Sensitivity { low, mid, high }

enum PhoneMount { seat, cupholder, holder }

enum DeviceRole { driver, passenger, research }

/// Локальные настройки приложения (хранятся на устройстве).
@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.locale, // null = язык системы
    this.voice = true,
    this.beep = true,
    this.warnDistanceM = 150,
    this.sensitivity = Sensitivity.mid,
    this.mount = PhoneMount.holder,
    this.role = DeviceRole.driver,
    this.reduceMotion = false,
    this.onboarded = false,
    this.autoRecord = true,
    this.carName,
    this.wheelbaseMm,
    this.tires,
    this.pressureBar,
    this.holiAsk = true,
    this.holiWake = false,
    this.holiEngine = 'auto',
  });

  final ThemeMode themeMode;
  final Locale? locale;
  final bool voice, beep, reduceMotion, onboarded, autoRecord;
  final int warnDistanceM; // 100..300 (этап 2: используется в /drive/ahead)
  final Sensitivity sensitivity;
  final PhoneMount mount;
  final DeviceRole role;
  final String? carName;
  final int? wheelbaseMm;
  final String? tires;
  final double? pressureBar;
  final bool holiAsk; // Холи спрашивает «да/нет» после ударов, похожих на яму
  final bool holiWake; // слушать «Привет, Холи» (только пока экран включён)
  final String holiEngine; // распознавание речи: auto | device | cloud

  AppSettings copyWith({
    ThemeMode? themeMode,
    Object? locale = _keep,
    bool? voice,
    bool? beep,
    int? warnDistanceM,
    Sensitivity? sensitivity,
    PhoneMount? mount,
    DeviceRole? role,
    bool? reduceMotion,
    bool? onboarded,
    bool? autoRecord,
    Object? carName = _keep,
    Object? wheelbaseMm = _keep,
    Object? tires = _keep,
    Object? pressureBar = _keep,
    bool? holiAsk,
    bool? holiWake,
    String? holiEngine,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        locale: identical(locale, _keep) ? this.locale : locale as Locale?,
        voice: voice ?? this.voice,
        beep: beep ?? this.beep,
        warnDistanceM: warnDistanceM ?? this.warnDistanceM,
        sensitivity: sensitivity ?? this.sensitivity,
        mount: mount ?? this.mount,
        role: role ?? this.role,
        reduceMotion: reduceMotion ?? this.reduceMotion,
        onboarded: onboarded ?? this.onboarded,
        autoRecord: autoRecord ?? this.autoRecord,
        carName: identical(carName, _keep) ? this.carName : carName as String?,
        wheelbaseMm: identical(wheelbaseMm, _keep) ? this.wheelbaseMm : wheelbaseMm as int?,
        tires: identical(tires, _keep) ? this.tires : tires as String?,
        pressureBar: identical(pressureBar, _keep) ? this.pressureBar : pressureBar as double?,
        holiAsk: holiAsk ?? this.holiAsk,
        holiWake: holiWake ?? this.holiWake,
        holiEngine: holiEngine ?? this.holiEngine,
      );
}

const _keep = Object();

final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError('override in main()'));

class SettingsNotifier extends Notifier<AppSettings> {
  late SharedPreferences _p;

  @override
  AppSettings build() {
    _p = ref.watch(prefsProvider);
    final loc = _p.getString('locale');
    return AppSettings(
      themeMode: ThemeMode.values.byName(_p.getString('theme') ?? 'system'),
      locale: loc == null ? null : Locale(loc),
      voice: _p.getBool('voice') ?? true,
      beep: _p.getBool('beep') ?? true,
      warnDistanceM: _p.getInt('warnDist') ?? 150,
      sensitivity: Sensitivity.values.byName(_p.getString('sens') ?? 'mid'),
      mount: PhoneMount.values.byName(_p.getString('mount') ?? 'holder'),
      role: DeviceRole.values.byName(_p.getString('role') ?? 'driver'),
      reduceMotion: _p.getBool('reduceMotion') ?? false,
      onboarded: _p.getBool('onboarded') ?? false,
      autoRecord: _p.getBool('autoRecord') ?? true,
      carName: _p.getString('carName'),
      wheelbaseMm: _p.getInt('wheelbaseMm'),
      tires: _p.getString('tires'),
      pressureBar: _p.getDouble('pressureBar'),
      holiAsk: _p.getBool('holiAsk') ?? true,
      holiWake: _p.getBool('holiWake') ?? false,
      holiEngine: _p.getString('holiEngine') ?? 'auto',
    );
  }

  void update(AppSettings Function(AppSettings s) f) {
    final s = f(state);
    state = s;
    _p.setString('theme', s.themeMode.name);
    s.locale == null ? _p.remove('locale') : _p.setString('locale', s.locale!.languageCode);
    _p.setBool('voice', s.voice);
    _p.setBool('beep', s.beep);
    _p.setInt('warnDist', s.warnDistanceM);
    _p.setString('sens', s.sensitivity.name);
    _p.setString('mount', s.mount.name);
    _p.setString('role', s.role.name);
    _p.setBool('reduceMotion', s.reduceMotion);
    _p.setBool('onboarded', s.onboarded);
    _p.setBool('autoRecord', s.autoRecord);
    _p.setBool('holiAsk', s.holiAsk);
    _p.setBool('holiWake', s.holiWake);
    _p.setString('holiEngine', s.holiEngine);
    _setOrRemove('carName', s.carName);
    _setOrRemove('tires', s.tires);
    s.wheelbaseMm == null ? _p.remove('wheelbaseMm') : _p.setInt('wheelbaseMm', s.wheelbaseMm!);
    s.pressureBar == null ? _p.remove('pressureBar') : _p.setDouble('pressureBar', s.pressureBar!);
  }

  void _setOrRemove(String k, String? v) => v == null ? _p.remove(k) : _p.setString(k, v);
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
