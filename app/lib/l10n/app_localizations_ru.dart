// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appName => 'Holescope';

  @override
  String get tagline => 'See every hole before you hit it.';

  @override
  String get tabMap => 'Карта';

  @override
  String get tabDrive => 'Поездка';

  @override
  String get tabStreets => 'Улицы';

  @override
  String get tabProfile => 'Профиль';

  @override
  String get newBadge => 'NEW';

  @override
  String get permLead =>
      'Разрешите датчики и геолокацию — так телефон почувствует яму, а вы увидите её на карте.';

  @override
  String get permMotionTitle => 'Движение и ориентация';

  @override
  String get permMotionSub => 'Определяем удар по подвеске';

  @override
  String get permLocTitle => 'Геолокация «всегда»';

  @override
  String get permLocSub => 'Запись в фоне';

  @override
  String get permNotifTitle => 'Уведомления';

  @override
  String get permNotifSub => 'Только предупреждения о ямах';

  @override
  String get permCta => 'Разрешить и начать';

  @override
  String get driveRecording => 'Запись идёт · экран можно заблокировать';

  @override
  String get driveIdle => 'Запись не идёт';

  @override
  String get kmh => 'км/ч';

  @override
  String get driveFound => 'Найдено ям';

  @override
  String get driveDistance => 'Пройдено';

  @override
  String kmValue(String value) {
    return '$value км';
  }

  @override
  String mValue(String value) {
    return '$value м';
  }

  @override
  String get driveStop => 'Остановить поездку';

  @override
  String get driveStart => 'Начать поездку';

  @override
  String get myFindsToday => 'Мои находки сегодня';

  @override
  String get searchHint => 'Поиск улицы или района';

  @override
  String get levelLight => 'Мелкая яма';

  @override
  String get levelMid => 'Средняя яма';

  @override
  String get levelDeep => 'Глубокая яма';

  @override
  String get levelDeepShort => 'Глубокая';

  @override
  String detectedDaysAgo(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n дня',
      many: '$n дней',
      few: '$n дня',
      one: '$n день',
    );
    return 'Обнаружена $_temp0 назад';
  }

  @override
  String driversCount(int n) {
    return '×$n водителей';
  }

  @override
  String get confirmedLabel => 'Подтвердили';

  @override
  String driversN(int n) {
    return '$n водителей';
  }

  @override
  String get statusLabel => 'Статус';

  @override
  String get statusOpen => 'Открыта';

  @override
  String get complaintsFiled => 'Жалоб подано';

  @override
  String get distanceLabel => 'Расстояние';

  @override
  String get potholeStillThere => 'Яма на месте';

  @override
  String get potholeFixed => 'Заделана';

  @override
  String get profileAnon => 'Анонимный профиль · без номера и почты';

  @override
  String get statFound => 'Найдено';

  @override
  String get statConfirmed => 'Подтв.';

  @override
  String get statKm => 'Км';

  @override
  String get myFinds => 'Мои находки';

  @override
  String myFindsSub(int n) {
    return '$n ям на карте';
  }

  @override
  String get settingsTitle => 'Настройки';

  @override
  String get settingsSub => 'Язык, звук, машина';

  @override
  String get warnAhead => 'Впереди яма';

  @override
  String get metersWord => 'метров';

  @override
  String get warnSlowDown => 'Снизьте скорость';

  @override
  String get warnDeepRight => 'Глубокая яма, правая полоса';

  @override
  String get speedLabel => 'Скорость';

  @override
  String get muteSound => 'Выключить звук';

  @override
  String get unmuteSound => 'Включить звук';

  @override
  String get setVoice => 'Голосовые предупреждения';

  @override
  String get setBeep => 'Звуковой сигнал';

  @override
  String setWarnDistance(int m) {
    return 'Предупреждать за $m м';
  }

  @override
  String setSensitivity(String v) {
    return 'Чувствительность: $v';
  }

  @override
  String get sensLow => 'низкая';

  @override
  String get sensMid => 'средняя';

  @override
  String get sensHigh => 'высокая';

  @override
  String setCarMount(String car, String mount) {
    return '$car · $mount';
  }

  @override
  String get setHint =>
      'Профиль машины и положение телефона помогают точнее определять ямы.';

  @override
  String get setLanguage => 'Язык';

  @override
  String get setTheme => 'Тема';

  @override
  String get themeSystem => 'Системная';

  @override
  String get themeDark => 'Тёмная';

  @override
  String get themeLight => 'Светлая';

  @override
  String get langSystem => 'Язык системы';

  @override
  String get setReduceMotion => 'Меньше анимации';

  @override
  String get complaintTitle => 'Жалоба в один клик';

  @override
  String get complaintSub => 'Текст и координаты подготовлены автоматически';

  @override
  String get draft => 'Черновик';

  @override
  String complaintDraftText(String street, int n, int days) {
    return 'На $street обнаружена глубокая яма. Подтверждена $n водителями за $days дн. Координаты и данные датчиков приложены.';
  }

  @override
  String get photo => 'Фото';

  @override
  String get optional => 'Необязательно';

  @override
  String get anonymous => 'Анонимно';

  @override
  String get yes => 'Да';

  @override
  String get complaintSend => 'Отправить жалобу';

  @override
  String get streetsTitle => 'Худшие улицы';

  @override
  String get streetsSub => 'Ям на километр за 30 дней';

  @override
  String get segCity => 'Город';

  @override
  String get segDistrict => 'Район';

  @override
  String get statusChainTitle => 'Нашли → Подали → Исправили';

  @override
  String get stepFound => 'Нашли';

  @override
  String get stepFiled => 'Подали';

  @override
  String get stepReview => 'Рассмотрение';

  @override
  String get stepFixed => 'Исправили';

  @override
  String get stepFixedWait => 'Ждём подтверждения водителей';

  @override
  String get shareChain => 'Поделиться цепочкой';

  @override
  String get routeTitle => 'Маршрут по качеству дороги';

  @override
  String get routeFast => 'Быстрый';

  @override
  String get routeSmooth => 'Ровный';

  @override
  String get routeGo => 'Поехать по ровному';

  @override
  String get notifTitle => 'Уведомления';

  @override
  String cityQuality(String month) {
    return 'Качество дорог · $month';
  }

  @override
  String get challengesTitle => 'Челленджи';

  @override
  String get challengesSub => 'Солидарность водителей';

  @override
  String get topDrivers => 'Топ водителей';

  @override
  String get confirmationsWord => 'подтверждений';

  @override
  String get weeklyReport => 'Отчёт недели';

  @override
  String get weeklyFound => 'найдено';

  @override
  String get weeklyComplaints => 'жалоб';

  @override
  String get vehicleTitle => 'Моя машина';

  @override
  String get vehicleModel => 'Модель';

  @override
  String get vehicleWheelbase => 'Колёсная база';

  @override
  String get vehicleTires => 'Шины';

  @override
  String get vehiclePressure => 'Давление';

  @override
  String get vehicleSuspension => 'Подвеска';

  @override
  String get vehicleSuspensionNote =>
      'Класс подвески считается по данным поездок и пока не определён.';

  @override
  String get vehicleNotSet => 'Не указано';

  @override
  String get vehicleUnverified => 'Характеристики не подтверждены';

  @override
  String get vehicleSave => 'Сохранить';

  @override
  String get vehicleSoftness => 'Индекс мягкости';

  @override
  String get vehicleSoftnessEmpty =>
      'Недостаточно данных: нужны поездки и сравнение с другими машинами.';

  @override
  String get questionTitle => 'Что это было?';

  @override
  String get questionSub => 'Ответьте после остановки — это учит Holescope';

  @override
  String get optPotholeLight => 'Мелкая яма';

  @override
  String get optPotholeMid => 'Средняя яма';

  @override
  String get optPotholeDeep => 'Глубокая яма';

  @override
  String get optBump => 'Лежачий полицейский';

  @override
  String get optManhole => 'Люк';

  @override
  String get optRail => 'Рельсы';

  @override
  String get optNothing => 'Ничего';

  @override
  String get optNotSure => 'Не знаю';

  @override
  String get tripSummary => 'Итоги поездки';

  @override
  String get tripKm => 'Километров';

  @override
  String get tripPotholes => 'Ям';

  @override
  String get tripPerKm => 'Ям на км';

  @override
  String get tripWorst => 'Самый плохой участок';

  @override
  String get tripRoughness => 'Ровность';

  @override
  String get tripDone => 'Готово';

  @override
  String get mountTitle => 'Где лежит телефон?';

  @override
  String get mountSeat => 'На сиденье';

  @override
  String get mountCupholder => 'В подстаканнике';

  @override
  String get mountHolder => 'В держателе';

  @override
  String get mountSub => 'От этого зависит чувствительность датчиков';

  @override
  String get roleTitle => 'Ваша роль';

  @override
  String get roleDriver => 'Водитель';

  @override
  String get roleDriverSub => 'Я за рулём своей машины';

  @override
  String get rolePassenger => 'Пассажир';

  @override
  String get rolePassengerSub => 'Такси или чужая машина';

  @override
  String get demoBanner => 'Демо-данные: сервер пока не подключён';

  @override
  String get cancel => 'Отмена';

  @override
  String get todoBackend => 'TODO: данные придут с сервера';

  @override
  String weeklyFixedTitle(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n ямы',
      many: '$n ям',
      few: '$n ямы',
      one: '$n яма',
    );
    return '$_temp0';
  }

  @override
  String weeklyFixedSub(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'исправлены',
      many: 'исправлено',
      few: 'исправлены',
      one: 'исправлена',
    );
    return '$_temp0 благодаря водителям Ташкента';
  }

  @override
  String get monthOctober => 'октябрь';

  @override
  String ttsAhead(int distance) {
    return 'Впереди яма, $distance метров';
  }

  @override
  String ttsAheadSlow(int distance, int safe) {
    return 'Впереди яма, $distance метров. Снизьте скорость до $safe';
  }

  @override
  String get notifRecording => 'Holescope записывает дорогу';

  @override
  String get notifWaiting => 'Holescope ждёт поездку';

  @override
  String get permDenied =>
      'Без этого разрешения запись невозможна. Откройте настройки и разрешите доступ.';

  @override
  String get openSettings => 'Открыть настройки';

  @override
  String get autoRecord => 'Автозапись поездок';

  @override
  String get tripsHistory => 'Поездки';

  @override
  String syncQueue(int n) {
    return 'В очереди на отправку: $n';
  }

  @override
  String get levelDanger => 'Опасная яма';

  @override
  String get sideLeft => 'слева';

  @override
  String get sideRight => 'справа';

  @override
  String get sideCenter => 'по центру';

  @override
  String warnSideLine(String level, String side) {
    return '$level, $side';
  }

  @override
  String get manualStartHint =>
      'Запись начнётся автоматически, когда вы поедете';

  @override
  String get questionsEmpty => 'Вопросов пока нет';

  @override
  String get roleResearch => 'Исследовательский логгер';

  @override
  String get roleResearchSub => 'Отправляет сырые данные для обучения';

  @override
  String get skipTrip => 'Не записывать эту поездку';

  @override
  String tripKmShort(String value) {
    return '$value км';
  }

  @override
  String get driveDetecting => 'Определяем поездку…';

  @override
  String get profileNoNick => 'Анонимный водитель';

  @override
  String get noPotholesNearby => 'Рядом ям не найдено';

  @override
  String get reportThanks => 'Спасибо, отметка принята';

  @override
  String get reportAlready => 'Сегодня вы уже отмечали эту яму';

  @override
  String get noConnection => 'Нет связи с сервером';

  @override
  String get retry => 'Повторить';

  @override
  String get streetsEmpty => 'Пока мало данных: нужны проезды по улицам';

  @override
  String get statusComplaintFiled => 'Жалоба подана';

  @override
  String get searchNoResults => 'Ничего не найдено';

  @override
  String get searchTitle => 'Улица или район';

  @override
  String get perKmUnit => 'ям/км';

  @override
  String get cityScoreEmpty => 'Недостаточно данных по городу';

  @override
  String get complaintTextPlaceholder => 'Готовим текст жалобы…';

  @override
  String stepFoundSub(int n, String when) {
    return '$n водителей · $when';
  }

  @override
  String get stepFiledNone => 'Ещё не подана';

  @override
  String stepFiledVia(String channel, String number) {
    return '$channel · №$number';
  }

  @override
  String stepFiledPending(String channel) {
    return '$channel · ждёт регистрации';
  }

  @override
  String get stepReviewWait => 'Ожидаем ответ';

  @override
  String stepReviewDue(String date) {
    return 'Ответ до $date';
  }

  @override
  String daysAgoShort(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n дня назад',
      many: '$n дней назад',
      few: '$n дня назад',
      one: '$n день назад',
    );
    return '$_temp0';
  }

  @override
  String get today => 'сегодня';

  @override
  String get recentTrips => 'Последние поездки';

  @override
  String get tripsEmpty => 'Поездок пока нет';

  @override
  String coverageKm(String km) {
    return '$km км проездов';
  }

  @override
  String get daysUnit => 'дн.';

  @override
  String get holiName => 'Холи';

  @override
  String get holiListening => 'слушает';

  @override
  String get holiSpeaking => 'говорит';

  @override
  String get holiThinking => 'думает';

  @override
  String get holiCall => 'Позвать Холи';

  @override
  String holiHeard(String text) {
    return 'Вы сказали: «$text»';
  }

  @override
  String get holiHint =>
      'Скажите: яма, глубокая яма, лежачий, люк, рельсы, переезд — или оценку дороги: ровная, хорошая, плохая, разбитая';

  @override
  String get setHoliAsk => 'Холи спрашивает «да/нет» после удара';

  @override
  String get setHoliWake => 'Отзываться на «Привет, Холи» (пока экран включён)';

  @override
  String get loaderSearching => 'Ищем ямы рядом…';

  @override
  String get loaderScanning => 'Сканируем дорогу…';

  @override
  String get holiErrMic => 'Нет доступа к микрофону';

  @override
  String get holiErrMicBlocked => 'Микрофон запрещён в настройках телефона';

  @override
  String get holiErrUnavailable => 'На телефоне нет службы распознавания речи';

  @override
  String get holiErrLang =>
      'Узбекский язык не поддерживается распознаванием телефона';

  @override
  String get holiErrBusy => 'Распознавание занято, попробуйте ещё раз';

  @override
  String get holiErrNet => 'Нет связи с сервером';

  @override
  String get holiErrTimeout => 'Распознавание не запустилось';

  @override
  String get holiErrFailed => 'Не удалось распознать речь';

  @override
  String get holiOpenSettings => 'Открыть настройки';

  @override
  String get holiCheck => 'Проверка голоса';

  @override
  String get holiBtnDone => 'Готово';

  @override
  String get holiBtnSkip => 'Пропустить';

  @override
  String get holiBtnCancel => 'Отмена';

  @override
  String get setHoliEngine => 'Распознавание речи';

  @override
  String get holiEngineAuto => 'Автоматически';

  @override
  String get holiEngineDevice => 'На телефоне';

  @override
  String get holiEngineCloud => 'На сервере (лучше для узбекского)';

  @override
  String get vcTitle => 'Проверка голоса';

  @override
  String get vcMic => 'Микрофон';

  @override
  String get vcMicOk => 'Доступ есть';

  @override
  String get vcMicNo => 'Нет доступа';

  @override
  String get vcAllow => 'Разрешить';

  @override
  String get vcSpeech => 'Распознавание на телефоне';

  @override
  String get vcSpeechOk => 'Работает';

  @override
  String get vcSpeechNo => 'Недоступно';

  @override
  String get vcSound => 'Голос Холи';

  @override
  String get vcPlay => 'Проверить звук';

  @override
  String get vcListen => 'Проверить распознавание';

  @override
  String get vcListenHint => 'Нажмите и скажите: «глубокая яма» или «яма»';

  @override
  String get vcCloud => 'Проверить сервер';

  @override
  String get vcHeard => 'Услышано';

  @override
  String get vcEngine => 'Распознавал';

  @override
  String get vcTime => 'Время';

  @override
  String get vcLog => 'Журнал';

  @override
  String get vcCopy => 'Скопировать журнал';

  @override
  String get vcCopied => 'Журнал скопирован';

  @override
  String get vcCommand => 'Команда';

  @override
  String get vcNone => 'команда не найдена';

  @override
  String get vcError => 'Ошибка';

  @override
  String get vcWorking => 'Слушаю…';

  @override
  String get optMore => 'Другие варианты';

  @override
  String get optLess => 'Свернуть';
}
