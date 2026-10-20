import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum Sensitivity { low, mid, high }

enum PhoneMount { seat, cupholder, holder, hand }

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
    this.holiVolume = 0.7,
    this.eventWindowS = 20,
    this.eventExtend = true,
    this.eventVibrate = true,
    this.eventVoiceReply = true,
    this.keepQueueH = 24,
    this.warnLight = false,
    this.warnMid = true,
    this.warnDeep = true,
    this.warnUseSpeed = true,
    this.notifPothole = true,
    this.notifQuestion = true,
    this.notifFixed = true,
    this.notifComplaint = true,
    this.notifWeekly = false,
    this.quietOn = true,
    this.quietFromH = 23,
    this.quietToH = 7,
    this.maxPerDay = 3,
    this.wifiOnly = true,
    this.textScale = 1.0,
    this.highContrast = false,
    this.carBig = true,
    this.carNight = true,
    this.carLock = true,
    this.keepScreenOn = true,
  });

  final ThemeMode themeMode;
  final Locale? locale;
  final bool voice, beep, reduceMotion, onboarded, autoRecord;
  final int warnDistanceM; // 100..300
  final Sensitivity sensitivity;
  final PhoneMount mount;
  final DeviceRole role;
  final String? carName;
  final int? wheelbaseMm;
  final String? tires;
  final double? pressureBar;
  final bool holiAsk; // Холи спрашивает «что это было?» после ударов
  final bool holiWake; // слушать «Привет, Холи» (только пока экран включён)
  final String holiEngine; // распознавание речи: auto | device | cloud
  final double holiVolume; // громкость голоса Холи 0.3..1
  // события и вопросы
  final int eventWindowS; // 10 | 20 | 30 — сколько живёт окно «что это было?»
  final bool eventExtend, eventVibrate, eventVoiceReply;
  final int keepQueueH; // сколько часов хранить неотвеченные вопросы
  // какие ямы показывать в предупреждениях
  final bool warnLight, warnMid, warnDeep, warnUseSpeed;
  // уведомления
  final bool notifPothole, notifQuestion, notifFixed, notifComplaint, notifWeekly;
  final bool quietOn;
  final int quietFromH, quietToH, maxPerDay;
  // данные и вид
  final bool wifiOnly; // отправлять поездки только по Wi-Fi
  final double textScale; // 0.85..1.4
  final bool highContrast;
  // режим в машине
  final bool carBig, carNight, carLock, keepScreenOn;

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
    double? holiVolume,
    int? eventWindowS,
    bool? eventExtend,
    bool? eventVibrate,
    bool? eventVoiceReply,
    int? keepQueueH,
    bool? warnLight,
    bool? warnMid,
    bool? warnDeep,
    bool? warnUseSpeed,
    bool? notifPothole,
    bool? notifQuestion,
    bool? notifFixed,
    bool? notifComplaint,
    bool? notifWeekly,
    bool? quietOn,
    int? quietFromH,
    int? quietToH,
    int? maxPerDay,
    bool? wifiOnly,
    double? textScale,
    bool? highContrast,
    bool? carBig,
    bool? carNight,
    bool? carLock,
    bool? keepScreenOn,
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
        holiVolume: holiVolume ?? this.holiVolume,
        eventWindowS: eventWindowS ?? this.eventWindowS,
        eventExtend: eventExtend ?? this.eventExtend,
        eventVibrate: eventVibrate ?? this.eventVibrate,
        eventVoiceReply: eventVoiceReply ?? this.eventVoiceReply,
        keepQueueH: keepQueueH ?? this.keepQueueH,
        warnLight: warnLight ?? this.warnLight,
        warnMid: warnMid ?? this.warnMid,
        warnDeep: warnDeep ?? this.warnDeep,
        warnUseSpeed: warnUseSpeed ?? this.warnUseSpeed,
        notifPothole: notifPothole ?? this.notifPothole,
        notifQuestion: notifQuestion ?? this.notifQuestion,
        notifFixed: notifFixed ?? this.notifFixed,
        notifComplaint: notifComplaint ?? this.notifComplaint,
        notifWeekly: notifWeekly ?? this.notifWeekly,
        quietOn: quietOn ?? this.quietOn,
        quietFromH: quietFromH ?? this.quietFromH,
        quietToH: quietToH ?? this.quietToH,
        maxPerDay: maxPerDay ?? this.maxPerDay,
        wifiOnly: wifiOnly ?? this.wifiOnly,
        textScale: textScale ?? this.textScale,
        highContrast: highContrast ?? this.highContrast,
        carBig: carBig ?? this.carBig,
        carNight: carNight ?? this.carNight,
        carLock: carLock ?? this.carLock,
        keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      );

  /// Тихие часы: сейчас можно присылать только срочное.
  bool inQuietHours(DateTime now) {
    if (!quietOn) return false;
    final h = now.hour;
    return quietFromH > quietToH ? (h >= quietFromH || h < quietToH) : (h >= quietFromH && h < quietToH);
  }
}

const _keep = Object();

final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError('override in main()'));

class SettingsNotifier extends Notifier<AppSettings> {
  late SharedPreferences _p;

  T _enum<T extends Enum>(List<T> values, String key, T def) {
    final v = _p.getString(key);
    for (final e in values) {
      if (e.name == v) return e;
    }
    return def;
  }

  @override
  AppSettings build() {
    _p = ref.watch(prefsProvider);
    final loc = _p.getString('locale');
    const d = AppSettings();
    bool b(String k, bool def) => _p.getBool(k) ?? def;
    int i(String k, int def) => _p.getInt(k) ?? def;
    return AppSettings(
      themeMode: _enum(ThemeMode.values, 'theme', ThemeMode.system),
      locale: loc == null ? null : Locale(loc),
      voice: b('voice', d.voice),
      beep: b('beep', d.beep),
      warnDistanceM: i('warnDist', d.warnDistanceM),
      sensitivity: _enum(Sensitivity.values, 'sens', Sensitivity.mid),
      mount: _enum(PhoneMount.values, 'mount', PhoneMount.holder),
      role: _enum(DeviceRole.values, 'role', DeviceRole.driver),
      reduceMotion: b('reduceMotion', d.reduceMotion),
      onboarded: b('onboarded', d.onboarded),
      autoRecord: b('autoRecord', d.autoRecord),
      carName: _p.getString('carName'),
      wheelbaseMm: _p.getInt('wheelbaseMm'),
      tires: _p.getString('tires'),
      pressureBar: _p.getDouble('pressureBar'),
      holiAsk: b('holiAsk', d.holiAsk),
      holiWake: b('holiWake', d.holiWake),
      holiEngine: _p.getString('holiEngine') ?? 'auto',
      holiVolume: _p.getDouble('holiVolume') ?? d.holiVolume,
      eventWindowS: i('eventWindowS', d.eventWindowS),
      eventExtend: b('eventExtend', d.eventExtend),
      eventVibrate: b('eventVibrate', d.eventVibrate),
      eventVoiceReply: b('eventVoiceReply', d.eventVoiceReply),
      keepQueueH: i('keepQueueH', d.keepQueueH),
      warnLight: b('warnLight', d.warnLight),
      warnMid: b('warnMid', d.warnMid),
      warnDeep: b('warnDeep', d.warnDeep),
      warnUseSpeed: b('warnUseSpeed', d.warnUseSpeed),
      notifPothole: b('notifPothole', d.notifPothole),
      notifQuestion: b('notifQuestion', d.notifQuestion),
      notifFixed: b('notifFixed', d.notifFixed),
      notifComplaint: b('notifComplaint', d.notifComplaint),
      notifWeekly: b('notifWeekly', d.notifWeekly),
      quietOn: b('quietOn', d.quietOn),
      quietFromH: i('quietFromH', d.quietFromH),
      quietToH: i('quietToH', d.quietToH),
      maxPerDay: i('maxPerDay', d.maxPerDay),
      wifiOnly: b('wifiOnly', d.wifiOnly),
      textScale: _p.getDouble('textScale') ?? d.textScale,
      highContrast: b('highContrast', d.highContrast),
      carBig: b('carBig', d.carBig),
      carNight: b('carNight', d.carNight),
      carLock: b('carLock', d.carLock),
      keepScreenOn: b('keepScreenOn', d.keepScreenOn),
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
    _p.setDouble('holiVolume', s.holiVolume);
    _p.setInt('eventWindowS', s.eventWindowS);
    _p.setBool('eventExtend', s.eventExtend);
    _p.setBool('eventVibrate', s.eventVibrate);
    _p.setBool('eventVoiceReply', s.eventVoiceReply);
    _p.setInt('keepQueueH', s.keepQueueH);
    _p.setBool('warnLight', s.warnLight);
    _p.setBool('warnMid', s.warnMid);
    _p.setBool('warnDeep', s.warnDeep);
    _p.setBool('warnUseSpeed', s.warnUseSpeed);
    _p.setBool('notifPothole', s.notifPothole);
    _p.setBool('notifQuestion', s.notifQuestion);
    _p.setBool('notifFixed', s.notifFixed);
    _p.setBool('notifComplaint', s.notifComplaint);
    _p.setBool('notifWeekly', s.notifWeekly);
    _p.setBool('quietOn', s.quietOn);
    _p.setInt('quietFromH', s.quietFromH);
    _p.setInt('quietToH', s.quietToH);
    _p.setInt('maxPerDay', s.maxPerDay);
    _p.setBool('wifiOnly', s.wifiOnly);
    _p.setDouble('textScale', s.textScale);
    _p.setBool('highContrast', s.highContrast);
    _p.setBool('carBig', s.carBig);
    _p.setBool('carNight', s.carNight);
    _p.setBool('carLock', s.carLock);
    _p.setBool('keepScreenOn', s.keepScreenOn);
    _setOrRemove('carName', s.carName);
    _setOrRemove('tires', s.tires);
    s.wheelbaseMm == null ? _p.remove('wheelbaseMm') : _p.setInt('wheelbaseMm', s.wheelbaseMm!);
    s.pressureBar == null ? _p.remove('pressureBar') : _p.setDouble('pressureBar', s.pressureBar!);
  }

  void _setOrRemove(String k, String? v) => v == null ? _p.remove(k) : _p.setString(k, v);
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
