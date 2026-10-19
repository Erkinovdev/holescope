import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ru.dart';
import 'app_localizations_uz.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ru'),
    Locale('uz'),
  ];

  /// No description provided for @appName.
  ///
  /// In ru, this message translates to:
  /// **'Holescope'**
  String get appName;

  /// No description provided for @tagline.
  ///
  /// In ru, this message translates to:
  /// **'See every hole before you hit it.'**
  String get tagline;

  /// No description provided for @tabMap.
  ///
  /// In ru, this message translates to:
  /// **'Карта'**
  String get tabMap;

  /// No description provided for @tabDrive.
  ///
  /// In ru, this message translates to:
  /// **'Поездка'**
  String get tabDrive;

  /// No description provided for @tabStreets.
  ///
  /// In ru, this message translates to:
  /// **'Улицы'**
  String get tabStreets;

  /// No description provided for @tabProfile.
  ///
  /// In ru, this message translates to:
  /// **'Профиль'**
  String get tabProfile;

  /// No description provided for @newBadge.
  ///
  /// In ru, this message translates to:
  /// **'NEW'**
  String get newBadge;

  /// No description provided for @permLead.
  ///
  /// In ru, this message translates to:
  /// **'Разрешите датчики и геолокацию — так телефон почувствует яму, а вы увидите её на карте.'**
  String get permLead;

  /// No description provided for @permMotionTitle.
  ///
  /// In ru, this message translates to:
  /// **'Движение и ориентация'**
  String get permMotionTitle;

  /// No description provided for @permMotionSub.
  ///
  /// In ru, this message translates to:
  /// **'Определяем удар по подвеске'**
  String get permMotionSub;

  /// No description provided for @permLocTitle.
  ///
  /// In ru, this message translates to:
  /// **'Геолокация «всегда»'**
  String get permLocTitle;

  /// No description provided for @permLocSub.
  ///
  /// In ru, this message translates to:
  /// **'Запись в фоне'**
  String get permLocSub;

  /// No description provided for @permNotifTitle.
  ///
  /// In ru, this message translates to:
  /// **'Уведомления'**
  String get permNotifTitle;

  /// No description provided for @permNotifSub.
  ///
  /// In ru, this message translates to:
  /// **'Только предупреждения о ямах'**
  String get permNotifSub;

  /// No description provided for @permCta.
  ///
  /// In ru, this message translates to:
  /// **'Разрешить и начать'**
  String get permCta;

  /// No description provided for @driveRecording.
  ///
  /// In ru, this message translates to:
  /// **'Запись идёт · экран можно заблокировать'**
  String get driveRecording;

  /// No description provided for @driveIdle.
  ///
  /// In ru, this message translates to:
  /// **'Запись не идёт'**
  String get driveIdle;

  /// No description provided for @kmh.
  ///
  /// In ru, this message translates to:
  /// **'км/ч'**
  String get kmh;

  /// No description provided for @driveFound.
  ///
  /// In ru, this message translates to:
  /// **'Найдено ям'**
  String get driveFound;

  /// No description provided for @driveDistance.
  ///
  /// In ru, this message translates to:
  /// **'Пройдено'**
  String get driveDistance;

  /// No description provided for @kmValue.
  ///
  /// In ru, this message translates to:
  /// **'{value} км'**
  String kmValue(String value);

  /// No description provided for @mValue.
  ///
  /// In ru, this message translates to:
  /// **'{value} м'**
  String mValue(String value);

  /// No description provided for @driveStop.
  ///
  /// In ru, this message translates to:
  /// **'Остановить поездку'**
  String get driveStop;

  /// No description provided for @driveStart.
  ///
  /// In ru, this message translates to:
  /// **'Начать поездку'**
  String get driveStart;

  /// No description provided for @myFindsToday.
  ///
  /// In ru, this message translates to:
  /// **'Мои находки сегодня'**
  String get myFindsToday;

  /// No description provided for @searchHint.
  ///
  /// In ru, this message translates to:
  /// **'Поиск улицы или района'**
  String get searchHint;

  /// No description provided for @levelLight.
  ///
  /// In ru, this message translates to:
  /// **'Мелкая яма'**
  String get levelLight;

  /// No description provided for @levelMid.
  ///
  /// In ru, this message translates to:
  /// **'Средняя яма'**
  String get levelMid;

  /// No description provided for @levelDeep.
  ///
  /// In ru, this message translates to:
  /// **'Глубокая яма'**
  String get levelDeep;

  /// No description provided for @levelDeepShort.
  ///
  /// In ru, this message translates to:
  /// **'Глубокая'**
  String get levelDeepShort;

  /// No description provided for @detectedDaysAgo.
  ///
  /// In ru, this message translates to:
  /// **'Обнаружена {n, plural, one{{n} день} few{{n} дня} many{{n} дней} other{{n} дня}} назад'**
  String detectedDaysAgo(int n);

  /// No description provided for @driversCount.
  ///
  /// In ru, this message translates to:
  /// **'×{n} водителей'**
  String driversCount(int n);

  /// No description provided for @confirmedLabel.
  ///
  /// In ru, this message translates to:
  /// **'Подтвердили'**
  String get confirmedLabel;

  /// No description provided for @driversN.
  ///
  /// In ru, this message translates to:
  /// **'{n} водителей'**
  String driversN(int n);

  /// No description provided for @statusLabel.
  ///
  /// In ru, this message translates to:
  /// **'Статус'**
  String get statusLabel;

  /// No description provided for @statusOpen.
  ///
  /// In ru, this message translates to:
  /// **'Открыта'**
  String get statusOpen;

  /// No description provided for @complaintsFiled.
  ///
  /// In ru, this message translates to:
  /// **'Жалоб подано'**
  String get complaintsFiled;

  /// No description provided for @distanceLabel.
  ///
  /// In ru, this message translates to:
  /// **'Расстояние'**
  String get distanceLabel;

  /// No description provided for @potholeStillThere.
  ///
  /// In ru, this message translates to:
  /// **'Яма на месте'**
  String get potholeStillThere;

  /// No description provided for @potholeFixed.
  ///
  /// In ru, this message translates to:
  /// **'Заделана'**
  String get potholeFixed;

  /// No description provided for @profileAnon.
  ///
  /// In ru, this message translates to:
  /// **'Анонимный профиль · без номера и почты'**
  String get profileAnon;

  /// No description provided for @statFound.
  ///
  /// In ru, this message translates to:
  /// **'Найдено'**
  String get statFound;

  /// No description provided for @statConfirmed.
  ///
  /// In ru, this message translates to:
  /// **'Подтв.'**
  String get statConfirmed;

  /// No description provided for @statKm.
  ///
  /// In ru, this message translates to:
  /// **'Км'**
  String get statKm;

  /// No description provided for @myFinds.
  ///
  /// In ru, this message translates to:
  /// **'Мои находки'**
  String get myFinds;

  /// No description provided for @myFindsSub.
  ///
  /// In ru, this message translates to:
  /// **'{n} ям на карте'**
  String myFindsSub(int n);

  /// No description provided for @settingsTitle.
  ///
  /// In ru, this message translates to:
  /// **'Настройки'**
  String get settingsTitle;

  /// No description provided for @settingsSub.
  ///
  /// In ru, this message translates to:
  /// **'Язык, звук, машина'**
  String get settingsSub;

  /// No description provided for @warnAhead.
  ///
  /// In ru, this message translates to:
  /// **'Впереди яма'**
  String get warnAhead;

  /// No description provided for @metersWord.
  ///
  /// In ru, this message translates to:
  /// **'метров'**
  String get metersWord;

  /// No description provided for @warnSlowDown.
  ///
  /// In ru, this message translates to:
  /// **'Снизьте скорость'**
  String get warnSlowDown;

  /// No description provided for @warnDeepRight.
  ///
  /// In ru, this message translates to:
  /// **'Глубокая яма, правая полоса'**
  String get warnDeepRight;

  /// No description provided for @speedLabel.
  ///
  /// In ru, this message translates to:
  /// **'Скорость'**
  String get speedLabel;

  /// No description provided for @muteSound.
  ///
  /// In ru, this message translates to:
  /// **'Выключить звук'**
  String get muteSound;

  /// No description provided for @unmuteSound.
  ///
  /// In ru, this message translates to:
  /// **'Включить звук'**
  String get unmuteSound;

  /// No description provided for @setVoice.
  ///
  /// In ru, this message translates to:
  /// **'Голосовые предупреждения'**
  String get setVoice;

  /// No description provided for @setBeep.
  ///
  /// In ru, this message translates to:
  /// **'Звуковой сигнал'**
  String get setBeep;

  /// No description provided for @setWarnDistance.
  ///
  /// In ru, this message translates to:
  /// **'Предупреждать за {m} м'**
  String setWarnDistance(int m);

  /// No description provided for @setSensitivity.
  ///
  /// In ru, this message translates to:
  /// **'Чувствительность: {v}'**
  String setSensitivity(String v);

  /// No description provided for @sensLow.
  ///
  /// In ru, this message translates to:
  /// **'низкая'**
  String get sensLow;

  /// No description provided for @sensMid.
  ///
  /// In ru, this message translates to:
  /// **'средняя'**
  String get sensMid;

  /// No description provided for @sensHigh.
  ///
  /// In ru, this message translates to:
  /// **'высокая'**
  String get sensHigh;

  /// No description provided for @setCarMount.
  ///
  /// In ru, this message translates to:
  /// **'{car} · {mount}'**
  String setCarMount(String car, String mount);

  /// No description provided for @setHint.
  ///
  /// In ru, this message translates to:
  /// **'Профиль машины и положение телефона помогают точнее определять ямы.'**
  String get setHint;

  /// No description provided for @setLanguage.
  ///
  /// In ru, this message translates to:
  /// **'Язык'**
  String get setLanguage;

  /// No description provided for @setTheme.
  ///
  /// In ru, this message translates to:
  /// **'Тема'**
  String get setTheme;

  /// No description provided for @themeSystem.
  ///
  /// In ru, this message translates to:
  /// **'Системная'**
  String get themeSystem;

  /// No description provided for @themeDark.
  ///
  /// In ru, this message translates to:
  /// **'Тёмная'**
  String get themeDark;

  /// No description provided for @themeLight.
  ///
  /// In ru, this message translates to:
  /// **'Светлая'**
  String get themeLight;

  /// No description provided for @langSystem.
  ///
  /// In ru, this message translates to:
  /// **'Язык системы'**
  String get langSystem;

  /// No description provided for @setReduceMotion.
  ///
  /// In ru, this message translates to:
  /// **'Меньше анимации'**
  String get setReduceMotion;

  /// No description provided for @complaintTitle.
  ///
  /// In ru, this message translates to:
  /// **'Жалоба в один клик'**
  String get complaintTitle;

  /// No description provided for @complaintSub.
  ///
  /// In ru, this message translates to:
  /// **'Текст и координаты подготовлены автоматически'**
  String get complaintSub;

  /// No description provided for @draft.
  ///
  /// In ru, this message translates to:
  /// **'Черновик'**
  String get draft;

  /// No description provided for @complaintDraftText.
  ///
  /// In ru, this message translates to:
  /// **'На {street} обнаружена глубокая яма. Подтверждена {n} водителями за {days} дн. Координаты и данные датчиков приложены.'**
  String complaintDraftText(String street, int n, int days);

  /// No description provided for @photo.
  ///
  /// In ru, this message translates to:
  /// **'Фото'**
  String get photo;

  /// No description provided for @optional.
  ///
  /// In ru, this message translates to:
  /// **'Необязательно'**
  String get optional;

  /// No description provided for @anonymous.
  ///
  /// In ru, this message translates to:
  /// **'Анонимно'**
  String get anonymous;

  /// No description provided for @yes.
  ///
  /// In ru, this message translates to:
  /// **'Да'**
  String get yes;

  /// No description provided for @complaintSend.
  ///
  /// In ru, this message translates to:
  /// **'Отправить жалобу'**
  String get complaintSend;

  /// No description provided for @streetsTitle.
  ///
  /// In ru, this message translates to:
  /// **'Худшие улицы'**
  String get streetsTitle;

  /// No description provided for @streetsSub.
  ///
  /// In ru, this message translates to:
  /// **'Ям на километр за 30 дней'**
  String get streetsSub;

  /// No description provided for @segCity.
  ///
  /// In ru, this message translates to:
  /// **'Город'**
  String get segCity;

  /// No description provided for @segDistrict.
  ///
  /// In ru, this message translates to:
  /// **'Район'**
  String get segDistrict;

  /// No description provided for @statusChainTitle.
  ///
  /// In ru, this message translates to:
  /// **'Нашли → Подали → Исправили'**
  String get statusChainTitle;

  /// No description provided for @stepFound.
  ///
  /// In ru, this message translates to:
  /// **'Нашли'**
  String get stepFound;

  /// No description provided for @stepFiled.
  ///
  /// In ru, this message translates to:
  /// **'Подали'**
  String get stepFiled;

  /// No description provided for @stepReview.
  ///
  /// In ru, this message translates to:
  /// **'Рассмотрение'**
  String get stepReview;

  /// No description provided for @stepFixed.
  ///
  /// In ru, this message translates to:
  /// **'Исправили'**
  String get stepFixed;

  /// No description provided for @stepFixedWait.
  ///
  /// In ru, this message translates to:
  /// **'Ждём подтверждения водителей'**
  String get stepFixedWait;

  /// No description provided for @shareChain.
  ///
  /// In ru, this message translates to:
  /// **'Поделиться цепочкой'**
  String get shareChain;

  /// No description provided for @routeTitle.
  ///
  /// In ru, this message translates to:
  /// **'Маршрут по качеству дороги'**
  String get routeTitle;

  /// No description provided for @routeFast.
  ///
  /// In ru, this message translates to:
  /// **'Быстрый'**
  String get routeFast;

  /// No description provided for @routeSmooth.
  ///
  /// In ru, this message translates to:
  /// **'Ровный'**
  String get routeSmooth;

  /// No description provided for @routeGo.
  ///
  /// In ru, this message translates to:
  /// **'Поехать по ровному'**
  String get routeGo;

  /// No description provided for @notifTitle.
  ///
  /// In ru, this message translates to:
  /// **'Уведомления'**
  String get notifTitle;

  /// No description provided for @cityQuality.
  ///
  /// In ru, this message translates to:
  /// **'Качество дорог · {month}'**
  String cityQuality(String month);

  /// No description provided for @challengesTitle.
  ///
  /// In ru, this message translates to:
  /// **'Челленджи'**
  String get challengesTitle;

  /// No description provided for @challengesSub.
  ///
  /// In ru, this message translates to:
  /// **'Солидарность водителей'**
  String get challengesSub;

  /// No description provided for @topDrivers.
  ///
  /// In ru, this message translates to:
  /// **'Топ водителей'**
  String get topDrivers;

  /// No description provided for @confirmationsWord.
  ///
  /// In ru, this message translates to:
  /// **'подтверждений'**
  String get confirmationsWord;

  /// No description provided for @weeklyReport.
  ///
  /// In ru, this message translates to:
  /// **'Отчёт недели'**
  String get weeklyReport;

  /// No description provided for @weeklyFound.
  ///
  /// In ru, this message translates to:
  /// **'найдено'**
  String get weeklyFound;

  /// No description provided for @weeklyComplaints.
  ///
  /// In ru, this message translates to:
  /// **'жалоб'**
  String get weeklyComplaints;

  /// No description provided for @vehicleTitle.
  ///
  /// In ru, this message translates to:
  /// **'Моя машина'**
  String get vehicleTitle;

  /// No description provided for @vehicleModel.
  ///
  /// In ru, this message translates to:
  /// **'Модель'**
  String get vehicleModel;

  /// No description provided for @vehicleWheelbase.
  ///
  /// In ru, this message translates to:
  /// **'Колёсная база'**
  String get vehicleWheelbase;

  /// No description provided for @vehicleTires.
  ///
  /// In ru, this message translates to:
  /// **'Шины'**
  String get vehicleTires;

  /// No description provided for @vehiclePressure.
  ///
  /// In ru, this message translates to:
  /// **'Давление'**
  String get vehiclePressure;

  /// No description provided for @vehicleSuspension.
  ///
  /// In ru, this message translates to:
  /// **'Подвеска'**
  String get vehicleSuspension;

  /// No description provided for @vehicleSuspensionNote.
  ///
  /// In ru, this message translates to:
  /// **'Класс подвески считается по данным поездок и пока не определён.'**
  String get vehicleSuspensionNote;

  /// No description provided for @vehicleNotSet.
  ///
  /// In ru, this message translates to:
  /// **'Не указано'**
  String get vehicleNotSet;

  /// No description provided for @vehicleUnverified.
  ///
  /// In ru, this message translates to:
  /// **'Характеристики не подтверждены'**
  String get vehicleUnverified;

  /// No description provided for @vehicleSave.
  ///
  /// In ru, this message translates to:
  /// **'Сохранить'**
  String get vehicleSave;

  /// No description provided for @vehicleSoftness.
  ///
  /// In ru, this message translates to:
  /// **'Индекс мягкости'**
  String get vehicleSoftness;

  /// No description provided for @vehicleSoftnessEmpty.
  ///
  /// In ru, this message translates to:
  /// **'Недостаточно данных: нужны поездки и сравнение с другими машинами.'**
  String get vehicleSoftnessEmpty;

  /// No description provided for @questionTitle.
  ///
  /// In ru, this message translates to:
  /// **'Что это было?'**
  String get questionTitle;

  /// No description provided for @questionSub.
  ///
  /// In ru, this message translates to:
  /// **'Ответьте после остановки — это учит Holescope'**
  String get questionSub;

  /// No description provided for @optPotholeLight.
  ///
  /// In ru, this message translates to:
  /// **'Мелкая яма'**
  String get optPotholeLight;

  /// No description provided for @optPotholeMid.
  ///
  /// In ru, this message translates to:
  /// **'Средняя яма'**
  String get optPotholeMid;

  /// No description provided for @optPotholeDeep.
  ///
  /// In ru, this message translates to:
  /// **'Глубокая яма'**
  String get optPotholeDeep;

  /// No description provided for @optBump.
  ///
  /// In ru, this message translates to:
  /// **'Лежачий полицейский'**
  String get optBump;

  /// No description provided for @optManhole.
  ///
  /// In ru, this message translates to:
  /// **'Люк'**
  String get optManhole;

  /// No description provided for @optRail.
  ///
  /// In ru, this message translates to:
  /// **'Рельсы'**
  String get optRail;

  /// No description provided for @optNothing.
  ///
  /// In ru, this message translates to:
  /// **'Ничего'**
  String get optNothing;

  /// No description provided for @optNotSure.
  ///
  /// In ru, this message translates to:
  /// **'Не знаю'**
  String get optNotSure;

  /// No description provided for @tripSummary.
  ///
  /// In ru, this message translates to:
  /// **'Итоги поездки'**
  String get tripSummary;

  /// No description provided for @tripKm.
  ///
  /// In ru, this message translates to:
  /// **'Километров'**
  String get tripKm;

  /// No description provided for @tripPotholes.
  ///
  /// In ru, this message translates to:
  /// **'Ям'**
  String get tripPotholes;

  /// No description provided for @tripPerKm.
  ///
  /// In ru, this message translates to:
  /// **'Ям на км'**
  String get tripPerKm;

  /// No description provided for @tripWorst.
  ///
  /// In ru, this message translates to:
  /// **'Самый плохой участок'**
  String get tripWorst;

  /// No description provided for @tripRoughness.
  ///
  /// In ru, this message translates to:
  /// **'Ровность'**
  String get tripRoughness;

  /// No description provided for @tripDone.
  ///
  /// In ru, this message translates to:
  /// **'Готово'**
  String get tripDone;

  /// No description provided for @mountTitle.
  ///
  /// In ru, this message translates to:
  /// **'Где лежит телефон?'**
  String get mountTitle;

  /// No description provided for @mountSeat.
  ///
  /// In ru, this message translates to:
  /// **'На сиденье'**
  String get mountSeat;

  /// No description provided for @mountCupholder.
  ///
  /// In ru, this message translates to:
  /// **'В подстаканнике'**
  String get mountCupholder;

  /// No description provided for @mountHolder.
  ///
  /// In ru, this message translates to:
  /// **'В держателе'**
  String get mountHolder;

  /// No description provided for @mountSub.
  ///
  /// In ru, this message translates to:
  /// **'От этого зависит чувствительность датчиков'**
  String get mountSub;

  /// No description provided for @roleTitle.
  ///
  /// In ru, this message translates to:
  /// **'Ваша роль'**
  String get roleTitle;

  /// No description provided for @roleDriver.
  ///
  /// In ru, this message translates to:
  /// **'Водитель'**
  String get roleDriver;

  /// No description provided for @roleDriverSub.
  ///
  /// In ru, this message translates to:
  /// **'Я за рулём своей машины'**
  String get roleDriverSub;

  /// No description provided for @rolePassenger.
  ///
  /// In ru, this message translates to:
  /// **'Пассажир'**
  String get rolePassenger;

  /// No description provided for @rolePassengerSub.
  ///
  /// In ru, this message translates to:
  /// **'Такси или чужая машина'**
  String get rolePassengerSub;

  /// No description provided for @demoBanner.
  ///
  /// In ru, this message translates to:
  /// **'Демо-данные: сервер пока не подключён'**
  String get demoBanner;

  /// No description provided for @cancel.
  ///
  /// In ru, this message translates to:
  /// **'Отмена'**
  String get cancel;

  /// No description provided for @todoBackend.
  ///
  /// In ru, this message translates to:
  /// **'TODO: данные придут с сервера'**
  String get todoBackend;

  /// No description provided for @weeklyFixedTitle.
  ///
  /// In ru, this message translates to:
  /// **'{n, plural, one{{n} яма} few{{n} ямы} many{{n} ям} other{{n} ямы}}'**
  String weeklyFixedTitle(int n);

  /// No description provided for @weeklyFixedSub.
  ///
  /// In ru, this message translates to:
  /// **'{n, plural, one{исправлена} few{исправлены} many{исправлено} other{исправлены}} благодаря водителям Ташкента'**
  String weeklyFixedSub(int n);

  /// No description provided for @monthOctober.
  ///
  /// In ru, this message translates to:
  /// **'октябрь'**
  String get monthOctober;

  /// No description provided for @ttsAhead.
  ///
  /// In ru, this message translates to:
  /// **'Впереди яма, {distance} метров'**
  String ttsAhead(int distance);

  /// No description provided for @ttsAheadSlow.
  ///
  /// In ru, this message translates to:
  /// **'Впереди яма, {distance} метров. Снизьте скорость до {safe}'**
  String ttsAheadSlow(int distance, int safe);

  /// No description provided for @notifRecording.
  ///
  /// In ru, this message translates to:
  /// **'Holescope записывает дорогу'**
  String get notifRecording;

  /// No description provided for @notifWaiting.
  ///
  /// In ru, this message translates to:
  /// **'Holescope ждёт поездку'**
  String get notifWaiting;

  /// No description provided for @permDenied.
  ///
  /// In ru, this message translates to:
  /// **'Без этого разрешения запись невозможна. Откройте настройки и разрешите доступ.'**
  String get permDenied;

  /// No description provided for @openSettings.
  ///
  /// In ru, this message translates to:
  /// **'Открыть настройки'**
  String get openSettings;

  /// No description provided for @autoRecord.
  ///
  /// In ru, this message translates to:
  /// **'Автозапись поездок'**
  String get autoRecord;

  /// No description provided for @tripsHistory.
  ///
  /// In ru, this message translates to:
  /// **'Поездки'**
  String get tripsHistory;

  /// No description provided for @syncQueue.
  ///
  /// In ru, this message translates to:
  /// **'В очереди на отправку: {n}'**
  String syncQueue(int n);

  /// No description provided for @levelDanger.
  ///
  /// In ru, this message translates to:
  /// **'Опасная яма'**
  String get levelDanger;

  /// No description provided for @sideLeft.
  ///
  /// In ru, this message translates to:
  /// **'слева'**
  String get sideLeft;

  /// No description provided for @sideRight.
  ///
  /// In ru, this message translates to:
  /// **'справа'**
  String get sideRight;

  /// No description provided for @sideCenter.
  ///
  /// In ru, this message translates to:
  /// **'по центру'**
  String get sideCenter;

  /// No description provided for @warnSideLine.
  ///
  /// In ru, this message translates to:
  /// **'{level}, {side}'**
  String warnSideLine(String level, String side);

  /// No description provided for @manualStartHint.
  ///
  /// In ru, this message translates to:
  /// **'Запись начнётся автоматически, когда вы поедете'**
  String get manualStartHint;

  /// No description provided for @questionsEmpty.
  ///
  /// In ru, this message translates to:
  /// **'Вопросов пока нет'**
  String get questionsEmpty;

  /// No description provided for @roleResearch.
  ///
  /// In ru, this message translates to:
  /// **'Исследовательский логгер'**
  String get roleResearch;

  /// No description provided for @roleResearchSub.
  ///
  /// In ru, this message translates to:
  /// **'Отправляет сырые данные для обучения'**
  String get roleResearchSub;

  /// No description provided for @skipTrip.
  ///
  /// In ru, this message translates to:
  /// **'Не записывать эту поездку'**
  String get skipTrip;

  /// No description provided for @tripKmShort.
  ///
  /// In ru, this message translates to:
  /// **'{value} км'**
  String tripKmShort(String value);

  /// No description provided for @driveDetecting.
  ///
  /// In ru, this message translates to:
  /// **'Определяем поездку…'**
  String get driveDetecting;

  /// No description provided for @profileNoNick.
  ///
  /// In ru, this message translates to:
  /// **'Анонимный водитель'**
  String get profileNoNick;

  /// No description provided for @noPotholesNearby.
  ///
  /// In ru, this message translates to:
  /// **'Рядом ям не найдено'**
  String get noPotholesNearby;

  /// No description provided for @reportThanks.
  ///
  /// In ru, this message translates to:
  /// **'Спасибо, отметка принята'**
  String get reportThanks;

  /// No description provided for @reportAlready.
  ///
  /// In ru, this message translates to:
  /// **'Сегодня вы уже отмечали эту яму'**
  String get reportAlready;

  /// No description provided for @noConnection.
  ///
  /// In ru, this message translates to:
  /// **'Нет связи с сервером'**
  String get noConnection;

  /// No description provided for @retry.
  ///
  /// In ru, this message translates to:
  /// **'Повторить'**
  String get retry;

  /// No description provided for @streetsEmpty.
  ///
  /// In ru, this message translates to:
  /// **'Пока мало данных: нужны проезды по улицам'**
  String get streetsEmpty;

  /// No description provided for @statusComplaintFiled.
  ///
  /// In ru, this message translates to:
  /// **'Жалоба подана'**
  String get statusComplaintFiled;

  /// No description provided for @searchNoResults.
  ///
  /// In ru, this message translates to:
  /// **'Ничего не найдено'**
  String get searchNoResults;

  /// No description provided for @searchTitle.
  ///
  /// In ru, this message translates to:
  /// **'Улица или район'**
  String get searchTitle;

  /// No description provided for @perKmUnit.
  ///
  /// In ru, this message translates to:
  /// **'ям/км'**
  String get perKmUnit;

  /// No description provided for @cityScoreEmpty.
  ///
  /// In ru, this message translates to:
  /// **'Недостаточно данных по городу'**
  String get cityScoreEmpty;

  /// No description provided for @complaintTextPlaceholder.
  ///
  /// In ru, this message translates to:
  /// **'Готовим текст жалобы…'**
  String get complaintTextPlaceholder;

  /// No description provided for @stepFoundSub.
  ///
  /// In ru, this message translates to:
  /// **'{n} водителей · {when}'**
  String stepFoundSub(int n, String when);

  /// No description provided for @stepFiledNone.
  ///
  /// In ru, this message translates to:
  /// **'Ещё не подана'**
  String get stepFiledNone;

  /// No description provided for @stepFiledVia.
  ///
  /// In ru, this message translates to:
  /// **'{channel} · №{number}'**
  String stepFiledVia(String channel, String number);

  /// No description provided for @stepFiledPending.
  ///
  /// In ru, this message translates to:
  /// **'{channel} · ждёт регистрации'**
  String stepFiledPending(String channel);

  /// No description provided for @stepReviewWait.
  ///
  /// In ru, this message translates to:
  /// **'Ожидаем ответ'**
  String get stepReviewWait;

  /// No description provided for @stepReviewDue.
  ///
  /// In ru, this message translates to:
  /// **'Ответ до {date}'**
  String stepReviewDue(String date);

  /// No description provided for @daysAgoShort.
  ///
  /// In ru, this message translates to:
  /// **'{n, plural, one{{n} день назад} few{{n} дня назад} many{{n} дней назад} other{{n} дня назад}}'**
  String daysAgoShort(int n);

  /// No description provided for @today.
  ///
  /// In ru, this message translates to:
  /// **'сегодня'**
  String get today;

  /// No description provided for @recentTrips.
  ///
  /// In ru, this message translates to:
  /// **'Последние поездки'**
  String get recentTrips;

  /// No description provided for @tripsEmpty.
  ///
  /// In ru, this message translates to:
  /// **'Поездок пока нет'**
  String get tripsEmpty;

  /// No description provided for @coverageKm.
  ///
  /// In ru, this message translates to:
  /// **'{km} км проездов'**
  String coverageKm(String km);

  /// No description provided for @daysUnit.
  ///
  /// In ru, this message translates to:
  /// **'дн.'**
  String get daysUnit;

  /// No description provided for @holiName.
  ///
  /// In ru, this message translates to:
  /// **'Холи'**
  String get holiName;

  /// No description provided for @holiListening.
  ///
  /// In ru, this message translates to:
  /// **'слушает'**
  String get holiListening;

  /// No description provided for @holiSpeaking.
  ///
  /// In ru, this message translates to:
  /// **'говорит'**
  String get holiSpeaking;

  /// No description provided for @holiThinking.
  ///
  /// In ru, this message translates to:
  /// **'думает'**
  String get holiThinking;

  /// No description provided for @holiCall.
  ///
  /// In ru, this message translates to:
  /// **'Позвать Холи'**
  String get holiCall;

  /// No description provided for @holiHeard.
  ///
  /// In ru, this message translates to:
  /// **'Вы сказали: «{text}»'**
  String holiHeard(String text);

  /// No description provided for @holiHint.
  ///
  /// In ru, this message translates to:
  /// **'Скажите: яма, глубокая яма, лежачий, люк, рельсы, переезд — или оценку дороги: ровная, хорошая, плохая, разбитая'**
  String get holiHint;

  /// No description provided for @setHoliAsk.
  ///
  /// In ru, this message translates to:
  /// **'Холи спрашивает «да/нет» после удара'**
  String get setHoliAsk;

  /// No description provided for @setHoliWake.
  ///
  /// In ru, this message translates to:
  /// **'Отзываться на «Привет, Холи» (пока экран включён)'**
  String get setHoliWake;

  /// No description provided for @loaderSearching.
  ///
  /// In ru, this message translates to:
  /// **'Ищем ямы рядом…'**
  String get loaderSearching;

  /// No description provided for @loaderScanning.
  ///
  /// In ru, this message translates to:
  /// **'Сканируем дорогу…'**
  String get loaderScanning;

  /// No description provided for @holiErrMic.
  ///
  /// In ru, this message translates to:
  /// **'Нет доступа к микрофону'**
  String get holiErrMic;

  /// No description provided for @holiErrMicBlocked.
  ///
  /// In ru, this message translates to:
  /// **'Микрофон запрещён в настройках телефона'**
  String get holiErrMicBlocked;

  /// No description provided for @holiErrUnavailable.
  ///
  /// In ru, this message translates to:
  /// **'На телефоне нет службы распознавания речи'**
  String get holiErrUnavailable;

  /// No description provided for @holiErrLang.
  ///
  /// In ru, this message translates to:
  /// **'Узбекский язык не поддерживается распознаванием телефона'**
  String get holiErrLang;

  /// No description provided for @holiErrBusy.
  ///
  /// In ru, this message translates to:
  /// **'Распознавание занято, попробуйте ещё раз'**
  String get holiErrBusy;

  /// No description provided for @holiErrNet.
  ///
  /// In ru, this message translates to:
  /// **'Нет связи с сервером'**
  String get holiErrNet;

  /// No description provided for @holiErrTimeout.
  ///
  /// In ru, this message translates to:
  /// **'Распознавание не запустилось'**
  String get holiErrTimeout;

  /// No description provided for @holiErrFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось распознать речь'**
  String get holiErrFailed;

  /// No description provided for @holiOpenSettings.
  ///
  /// In ru, this message translates to:
  /// **'Открыть настройки'**
  String get holiOpenSettings;

  /// No description provided for @holiCheck.
  ///
  /// In ru, this message translates to:
  /// **'Проверка голоса'**
  String get holiCheck;

  /// No description provided for @holiBtnDone.
  ///
  /// In ru, this message translates to:
  /// **'Готово'**
  String get holiBtnDone;

  /// No description provided for @holiBtnSkip.
  ///
  /// In ru, this message translates to:
  /// **'Пропустить'**
  String get holiBtnSkip;

  /// No description provided for @holiBtnCancel.
  ///
  /// In ru, this message translates to:
  /// **'Отмена'**
  String get holiBtnCancel;

  /// No description provided for @setHoliEngine.
  ///
  /// In ru, this message translates to:
  /// **'Распознавание речи'**
  String get setHoliEngine;

  /// No description provided for @holiEngineAuto.
  ///
  /// In ru, this message translates to:
  /// **'Автоматически'**
  String get holiEngineAuto;

  /// No description provided for @holiEngineDevice.
  ///
  /// In ru, this message translates to:
  /// **'На телефоне'**
  String get holiEngineDevice;

  /// No description provided for @holiEngineCloud.
  ///
  /// In ru, this message translates to:
  /// **'На сервере (лучше для узбекского)'**
  String get holiEngineCloud;

  /// No description provided for @vcTitle.
  ///
  /// In ru, this message translates to:
  /// **'Проверка голоса'**
  String get vcTitle;

  /// No description provided for @vcMic.
  ///
  /// In ru, this message translates to:
  /// **'Микрофон'**
  String get vcMic;

  /// No description provided for @vcMicOk.
  ///
  /// In ru, this message translates to:
  /// **'Доступ есть'**
  String get vcMicOk;

  /// No description provided for @vcMicNo.
  ///
  /// In ru, this message translates to:
  /// **'Нет доступа'**
  String get vcMicNo;

  /// No description provided for @vcAllow.
  ///
  /// In ru, this message translates to:
  /// **'Разрешить'**
  String get vcAllow;

  /// No description provided for @vcSpeech.
  ///
  /// In ru, this message translates to:
  /// **'Распознавание на телефоне'**
  String get vcSpeech;

  /// No description provided for @vcSpeechOk.
  ///
  /// In ru, this message translates to:
  /// **'Работает'**
  String get vcSpeechOk;

  /// No description provided for @vcSpeechNo.
  ///
  /// In ru, this message translates to:
  /// **'Недоступно'**
  String get vcSpeechNo;

  /// No description provided for @vcSound.
  ///
  /// In ru, this message translates to:
  /// **'Голос Холи'**
  String get vcSound;

  /// No description provided for @vcPlay.
  ///
  /// In ru, this message translates to:
  /// **'Проверить звук'**
  String get vcPlay;

  /// No description provided for @vcListen.
  ///
  /// In ru, this message translates to:
  /// **'Проверить распознавание'**
  String get vcListen;

  /// No description provided for @vcListenHint.
  ///
  /// In ru, this message translates to:
  /// **'Нажмите и скажите: «глубокая яма» или «яма»'**
  String get vcListenHint;

  /// No description provided for @vcCloud.
  ///
  /// In ru, this message translates to:
  /// **'Проверить сервер'**
  String get vcCloud;

  /// No description provided for @vcHeard.
  ///
  /// In ru, this message translates to:
  /// **'Услышано'**
  String get vcHeard;

  /// No description provided for @vcEngine.
  ///
  /// In ru, this message translates to:
  /// **'Распознавал'**
  String get vcEngine;

  /// No description provided for @vcTime.
  ///
  /// In ru, this message translates to:
  /// **'Время'**
  String get vcTime;

  /// No description provided for @vcLog.
  ///
  /// In ru, this message translates to:
  /// **'Журнал'**
  String get vcLog;

  /// No description provided for @vcCopy.
  ///
  /// In ru, this message translates to:
  /// **'Скопировать журнал'**
  String get vcCopy;

  /// No description provided for @vcCopied.
  ///
  /// In ru, this message translates to:
  /// **'Журнал скопирован'**
  String get vcCopied;

  /// No description provided for @vcCommand.
  ///
  /// In ru, this message translates to:
  /// **'Команда'**
  String get vcCommand;

  /// No description provided for @vcNone.
  ///
  /// In ru, this message translates to:
  /// **'команда не найдена'**
  String get vcNone;

  /// No description provided for @vcError.
  ///
  /// In ru, this message translates to:
  /// **'Ошибка'**
  String get vcError;

  /// No description provided for @vcWorking.
  ///
  /// In ru, this message translates to:
  /// **'Слушаю…'**
  String get vcWorking;

  /// No description provided for @optMore.
  ///
  /// In ru, this message translates to:
  /// **'Другие варианты'**
  String get optMore;

  /// No description provided for @optLess.
  ///
  /// In ru, this message translates to:
  /// **'Свернуть'**
  String get optLess;

  /// No description provided for @eventAskTitle.
  ///
  /// In ru, this message translates to:
  /// **'Что это было?'**
  String get eventAskTitle;

  /// No description provided for @eventAgo.
  ///
  /// In ru, this message translates to:
  /// **'{speed} км/ч · {sec} с назад'**
  String eventAgo(int speed, int sec);

  /// No description provided for @eventGuessHint.
  ///
  /// In ru, this message translates to:
  /// **'Похоже: {name} · {p}%'**
  String eventGuessHint(String name, int p);

  /// No description provided for @eventChosen.
  ///
  /// In ru, this message translates to:
  /// **'Записано: {name}'**
  String eventChosen(String name);

  /// No description provided for @eventViaVoice.
  ///
  /// In ru, this message translates to:
  /// **'выбрано голосом'**
  String get eventViaVoice;

  /// No description provided for @eventViaTap.
  ///
  /// In ru, this message translates to:
  /// **'выбрано нажатием'**
  String get eventViaTap;

  /// No description provided for @eventClose.
  ///
  /// In ru, this message translates to:
  /// **'Закрыть'**
  String get eventClose;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ru', 'uz'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ru':
      return AppLocalizationsRu();
    case 'uz':
      return AppLocalizationsUz();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
