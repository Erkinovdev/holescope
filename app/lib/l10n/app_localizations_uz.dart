// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Uzbek (`uz`).
class AppLocalizationsUz extends AppLocalizations {
  AppLocalizationsUz([String locale = 'uz']) : super(locale);

  @override
  String get appName => 'Holescope';

  @override
  String get tagline => 'See every hole before you hit it.';

  @override
  String get tabMap => 'Xarita';

  @override
  String get tabDrive => 'Safar';

  @override
  String get tabStreets => 'Ko‘chalar';

  @override
  String get tabProfile => 'Profil';

  @override
  String get newBadge => 'NEW';

  @override
  String get permLead =>
      'Harakat datchiklari va geolokatsiya telefon chuqurni sezishi, siz esa uni xaritada ko‘rishingiz va safar marshrutini yozishingiz uchun kerak.';

  @override
  String get permMotionTitle => 'Harakat va yo‘nalish';

  @override
  String get permMotionSub => 'Osma tizimiga zarbani aniqlaymiz';

  @override
  String get permLocTitle => 'Geolokatsiya «doim»';

  @override
  String get permLocSub => 'Fonda yozish';

  @override
  String get permNotifTitle => 'Bildirishnomalar';

  @override
  String get permNotifSub => 'Faqat chuqurlar haqida ogohlantirish';

  @override
  String get permCta => 'Davom etish';

  @override
  String get driveRecording => 'Yozish ketmoqda · ekranni qulflash mumkin';

  @override
  String get driveIdle => 'Yozish yo‘q';

  @override
  String get kmh => 'km/soat';

  @override
  String get driveFound => 'Topilgan chuqurlar';

  @override
  String get driveDistance => 'Bosib o‘tilgan';

  @override
  String kmValue(String value) {
    return '$value km';
  }

  @override
  String mValue(String value) {
    return '$value m';
  }

  @override
  String get driveStop => 'Safarni to‘xtatish';

  @override
  String get driveStart => 'Safarni boshlash';

  @override
  String get myFindsToday => 'Bugungi topilmalarim';

  @override
  String get searchHint => 'Ko‘cha yoki tumanni qidirish';

  @override
  String get levelLight => 'Kichik chuqur';

  @override
  String get levelMid => 'O‘rtacha chuqur';

  @override
  String get levelDeep => 'Chuqur o‘ra';

  @override
  String get levelDeepShort => 'Chuqur';

  @override
  String detectedDaysAgo(int n) {
    return '$n kun oldin aniqlangan';
  }

  @override
  String driversCount(int n) {
    return '×$n haydovchi';
  }

  @override
  String get confirmedLabel => 'Tasdiqlagan';

  @override
  String driversN(int n) {
    return '$n haydovchi';
  }

  @override
  String get statusLabel => 'Holati';

  @override
  String get statusOpen => 'Ochiq';

  @override
  String get complaintsFiled => 'Shikoyatlar soni';

  @override
  String get distanceLabel => 'Masofa';

  @override
  String get potholeStillThere => 'Chuqur joyida';

  @override
  String get potholeFixed => 'Ta’mirlangan';

  @override
  String get profileAnon => 'Anonim profil · raqam va pochtasiz';

  @override
  String get statFound => 'Topilgan';

  @override
  String get statConfirmed => 'Tasdiq.';

  @override
  String get statKm => 'Km';

  @override
  String get myFinds => 'Topilmalarim';

  @override
  String myFindsSub(int n) {
    return 'Xaritada $n ta chuqur';
  }

  @override
  String get settingsTitle => 'Sozlamalar';

  @override
  String get settingsSub => 'Til, ovoz, mashina';

  @override
  String get warnAhead => 'Oldinda chuqur';

  @override
  String get metersWord => 'metr';

  @override
  String get warnSlowDown => 'Tezlikni pasaytiring';

  @override
  String get warnDeepRight => 'Chuqur o‘ra, o‘ng qatorda';

  @override
  String get speedLabel => 'Tezlik';

  @override
  String get muteSound => 'Ovozni o‘chirish';

  @override
  String get unmuteSound => 'Ovozni yoqish';

  @override
  String get setVoice => 'Ovozli ogohlantirishlar';

  @override
  String get setBeep => 'Ovozli signal';

  @override
  String setWarnDistance(int m) {
    return '$m m oldin ogohlantirish';
  }

  @override
  String setSensitivity(String v) {
    return 'Sezgirlik: $v';
  }

  @override
  String get sensLow => 'past';

  @override
  String get sensMid => 'o‘rtacha';

  @override
  String get sensHigh => 'yuqori';

  @override
  String setCarMount(String car, String mount) {
    return '$car · $mount';
  }

  @override
  String get setHint =>
      'Mashina profili va telefon joylashuvi chuqurlarni aniqroq topishga yordam beradi.';

  @override
  String get setLanguage => 'Til';

  @override
  String get setTheme => 'Mavzu';

  @override
  String get themeSystem => 'Tizim';

  @override
  String get themeDark => 'Qorong‘i';

  @override
  String get themeLight => 'Yorug‘';

  @override
  String get langSystem => 'Tizim tili';

  @override
  String get setReduceMotion => 'Animatsiyani kamaytirish';

  @override
  String get complaintTitle => 'Bir bosishda shikoyat';

  @override
  String get complaintSub => 'Matn va koordinatalar avtomatik tayyorlandi';

  @override
  String get draft => 'Qoralama';

  @override
  String complaintDraftText(String street, int n, int days) {
    return '$street manzilida chuqur o‘ra aniqlandi. $days kun ichida $n haydovchi tasdiqladi. Koordinatalar va datchik ma’lumotlari ilova qilingan.';
  }

  @override
  String get photo => 'Rasm';

  @override
  String get optional => 'Majburiy emas';

  @override
  String get anonymous => 'Anonim';

  @override
  String get yes => 'Ha';

  @override
  String get complaintSend => 'Shikoyat yuborish';

  @override
  String get streetsTitle => 'Eng yomon ko‘chalar';

  @override
  String get streetsSub => '30 kunda har kilometrdagi chuqurlar';

  @override
  String get segCity => 'Shahar';

  @override
  String get segDistrict => 'Tuman';

  @override
  String get statusChainTitle => 'Topdik → Topshirdik → Tuzatdik';

  @override
  String get stepFound => 'Topdik';

  @override
  String get stepFiled => 'Topshirdik';

  @override
  String get stepReview => 'Ko‘rib chiqilmoqda';

  @override
  String get stepFixed => 'Tuzatdik';

  @override
  String get stepFixedWait => 'Haydovchilar tasdig‘i kutilmoqda';

  @override
  String get shareChain => 'Zanjirni ulashish';

  @override
  String get routeTitle => 'Yo‘l sifati bo‘yicha marshrut';

  @override
  String get routeFast => 'Tezkor';

  @override
  String get routeSmooth => 'Tekis';

  @override
  String get routeGo => 'Tekis yo‘ldan borish';

  @override
  String get notifTitle => 'Bildirishnomalar';

  @override
  String cityQuality(String month) {
    return 'Yo‘llar sifati · $month';
  }

  @override
  String get challengesTitle => 'Chellenjlar';

  @override
  String get challengesSub => 'Haydovchilar hamjihatligi';

  @override
  String get topDrivers => 'Eng yaxshi haydovchilar';

  @override
  String get confirmationsWord => 'tasdiq';

  @override
  String get weeklyReport => 'Haftalik hisobot';

  @override
  String get weeklyFound => 'topilgan';

  @override
  String get weeklyComplaints => 'shikoyat';

  @override
  String get vehicleTitle => 'Mening mashinam';

  @override
  String get vehicleModel => 'Model';

  @override
  String get vehicleWheelbase => 'G‘ildirak bazasi';

  @override
  String get vehicleTires => 'Shinalar';

  @override
  String get vehiclePressure => 'Bosim';

  @override
  String get vehicleSuspension => 'Osma tizimi';

  @override
  String get vehicleSuspensionNote =>
      'Osma tizimi sinfi safarlar ma’lumotidan hisoblanadi, hozircha aniqlanmagan.';

  @override
  String get vehicleNotSet => 'Ko‘rsatilmagan';

  @override
  String get vehicleUnverified => 'Xususiyatlar tasdiqlanmagan';

  @override
  String get vehicleSave => 'Saqlash';

  @override
  String get vehicleSoftness => 'Yumshoqlik indeksi';

  @override
  String get vehicleSoftnessEmpty =>
      'Ma’lumot yetarli emas: safarlar va boshqa mashinalar bilan solishtirish kerak.';

  @override
  String get questionTitle => 'Bu nima edi?';

  @override
  String get questionSub =>
      'To‘xtagandan keyin javob bering — bu Holescope’ni o‘rgatadi';

  @override
  String get optPotholeLight => 'Kichik chuqur';

  @override
  String get optPotholeMid => 'O‘rtacha chuqur';

  @override
  String get optPotholeDeep => 'Chuqur o‘ra';

  @override
  String get optBump => 'Tezlikni pasaytirgich';

  @override
  String get optManhole => 'Lyuk';

  @override
  String get optRail => 'Rels';

  @override
  String get optNothing => 'Hech narsa';

  @override
  String get optNotSure => 'Bilmayman';

  @override
  String get tripSummary => 'Safar yakunlari';

  @override
  String get tripKm => 'Kilometr';

  @override
  String get tripPotholes => 'Chuqurlar';

  @override
  String get tripPerKm => 'Km ga chuqur';

  @override
  String get tripWorst => 'Eng yomon uchastka';

  @override
  String get tripRoughness => 'Tekislik';

  @override
  String get tripDone => 'Tayyor';

  @override
  String get mountTitle => 'Telefon qayerda turibdi?';

  @override
  String get mountSeat => 'O‘rindiqda';

  @override
  String get mountCupholder => 'Stakan ushlagichda';

  @override
  String get mountHolder => 'Ushlagichda';

  @override
  String get mountSub => 'Datchiklar sezgirligi shunga bog‘liq';

  @override
  String get roleTitle => 'Sizning rolingiz';

  @override
  String get roleDriver => 'Haydovchi';

  @override
  String get roleDriverSub => 'O‘z mashinamni boshqaraman';

  @override
  String get rolePassenger => 'Yo‘lovchi';

  @override
  String get rolePassengerSub => 'Taksi yoki begona mashina';

  @override
  String get demoBanner => 'Demo ma’lumotlar: server hali ulanmagan';

  @override
  String get cancel => 'Bekor qilish';

  @override
  String get todoBackend => 'TODO: ma’lumot serverdan keladi';

  @override
  String weeklyFixedTitle(int n) {
    return '$n ta chuqur';
  }

  @override
  String weeklyFixedSub(int n) {
    return 'Toshkent haydovchilari sharofati bilan ta’mirlandi';
  }

  @override
  String get monthOctober => 'oktabr';

  @override
  String ttsAhead(int distance) {
    return 'Oldinda chuqur, $distance metr';
  }

  @override
  String ttsAheadSlow(int distance, int safe) {
    return 'Oldinda chuqur, $distance metr. Tezlikni $safe gacha pasaytiring';
  }

  @override
  String get notifRecording => 'Holescope yo‘lni yozmoqda';

  @override
  String get notifWaiting => 'Holescope safarni kutmoqda';

  @override
  String get permDenied =>
      'Bu funksiya uchun geolokatsiya kerak. Uni ilova sozlamalarida yoqish mumkin.';

  @override
  String get openSettings => 'Sozlamalarni ochish';

  @override
  String get autoRecord => 'Safarlarni avtomatik yozish';

  @override
  String get tripsHistory => 'Safarlar';

  @override
  String syncQueue(int n) {
    return 'Yuborish navbatida: $n';
  }

  @override
  String get levelDanger => 'Xavfli chuqur';

  @override
  String get sideLeft => 'chapda';

  @override
  String get sideRight => 'o‘ngda';

  @override
  String get sideCenter => 'o‘rtada';

  @override
  String warnSideLine(String level, String side) {
    return '$level, $side';
  }

  @override
  String get manualStartHint =>
      'Siz yo‘lga chiqqaningizda yozish avtomatik boshlanadi';

  @override
  String get questionsEmpty => 'Hozircha savollar yo‘q';

  @override
  String get roleResearch => 'Tadqiqot logeri';

  @override
  String get roleResearchSub => 'O‘qitish uchun xom ma’lumot yuboradi';

  @override
  String get skipTrip => 'Bu safarni yozmaslik';

  @override
  String tripKmShort(String value) {
    return '$value km';
  }

  @override
  String get driveDetecting => 'Safar aniqlanmoqda…';

  @override
  String get profileNoNick => 'Anonim haydovchi';

  @override
  String get noPotholesNearby => 'Yaqin atrofda chuqur topilmadi';

  @override
  String get reportThanks => 'Rahmat, belgi qabul qilindi';

  @override
  String get reportAlready => 'Bugun bu chuqurni allaqachon belgilagansiz';

  @override
  String get noConnection => 'Server bilan aloqa yo‘q';

  @override
  String get retry => 'Qayta urinish';

  @override
  String get streetsEmpty =>
      'Hozircha ma’lumot kam: ko‘chalar bo‘ylab safarlar kerak';

  @override
  String get statusComplaintFiled => 'Shikoyat topshirilgan';

  @override
  String get searchNoResults => 'Hech narsa topilmadi';

  @override
  String get searchTitle => 'Ko‘cha yoki tuman';

  @override
  String get perKmUnit => 'chuqur/km';

  @override
  String get cityScoreEmpty => 'Shahar bo‘yicha ma’lumot yetarli emas';

  @override
  String get complaintTextPlaceholder => 'Shikoyat matni tayyorlanmoqda…';

  @override
  String stepFoundSub(int n, String when) {
    return '$n haydovchi · $when';
  }

  @override
  String get stepFiledNone => 'Hali topshirilmagan';

  @override
  String stepFiledVia(String channel, String number) {
    return '$channel · №$number';
  }

  @override
  String stepFiledPending(String channel) {
    return '$channel · ro‘yxatdan o‘tishni kutmoqda';
  }

  @override
  String get stepReviewWait => 'Javob kutilmoqda';

  @override
  String stepReviewDue(String date) {
    return 'Javob $date gacha';
  }

  @override
  String daysAgoShort(int n) {
    return '$n kun oldin';
  }

  @override
  String get today => 'bugun';

  @override
  String get recentTrips => 'So‘nggi safarlar';

  @override
  String get tripsEmpty => 'Hozircha safarlar yo‘q';

  @override
  String coverageKm(String km) {
    return '$km km yo‘l o‘tilgan';
  }

  @override
  String get daysUnit => 'kun';

  @override
  String get holiName => 'Xoli';

  @override
  String get holiListening => 'tinglayapti';

  @override
  String get holiSpeaking => 'gapiryapti';

  @override
  String get holiThinking => 'o‘ylayapti';

  @override
  String get holiCall => 'Xolini chaqirish';

  @override
  String holiHeard(String text) {
    return 'Siz aytdingiz: «$text»';
  }

  @override
  String get holiHint =>
      'Ayting: o‘ra, chuqur o‘ra, yotiq politsiyachi, lyuk, relslar yoki yo‘l bahosi: tekis, yaxshi, yomon, buzilgan';

  @override
  String get setHoliAsk => 'Zarbadan keyin Xoli «ha/yo‘q» deb so‘raydi';

  @override
  String get setHoliWake =>
      '«Salom, Xoli» ga javob berish (ekran yoniq bo‘lganda)';

  @override
  String get loaderSearching => 'Atrofdagi o‘ralarni qidiramiz…';

  @override
  String get loaderScanning => 'Yo‘lni skanerlaymiz…';

  @override
  String get holiErrMic => 'Mikrofonga ruxsat yo‘q';

  @override
  String get holiErrMicBlocked => 'Mikrofon telefon sozlamalarida taqiqlangan';

  @override
  String get holiErrUnavailable => 'Telefonda nutqni aniqlash xizmati yo‘q';

  @override
  String get holiErrLang => 'Telefon o‘zbek tilini aniqlay olmaydi';

  @override
  String get holiErrBusy => 'Aniqlash band, qayta urinib ko‘ring';

  @override
  String get holiErrNet => 'Server bilan aloqa yo‘q';

  @override
  String get holiErrTimeout => 'Aniqlash ishga tushmadi';

  @override
  String get holiErrFailed => 'Nutqni aniqlab bo‘lmadi';

  @override
  String get holiOpenSettings => 'Sozlamalarni ochish';

  @override
  String get holiCheck => 'Ovozni tekshirish';

  @override
  String get holiBtnDone => 'Tayyor';

  @override
  String get holiBtnSkip => 'O‘tkazib yuborish';

  @override
  String get holiBtnCancel => 'Bekor qilish';

  @override
  String get setHoliEngine => 'Nutqni aniqlash';

  @override
  String get holiEngineAuto => 'Avtomatik';

  @override
  String get holiEngineDevice => 'Telefonda';

  @override
  String get holiEngineCloud => 'Serverda (o‘zbek tili uchun yaxshiroq)';

  @override
  String get vcTitle => 'Ovozni tekshirish';

  @override
  String get vcMic => 'Mikrofon';

  @override
  String get vcMicOk => 'Ruxsat bor';

  @override
  String get vcMicNo => 'Ruxsat yo‘q';

  @override
  String get vcAllow => 'Davom etish';

  @override
  String get vcSpeech => 'Telefonda aniqlash';

  @override
  String get vcSpeechOk => 'Ishlayapti';

  @override
  String get vcSpeechNo => 'Mavjud emas';

  @override
  String get vcSound => 'Xoli ovozi';

  @override
  String get vcPlay => 'Ovozni tekshirish';

  @override
  String get vcListen => 'Aniqlashni tekshirish';

  @override
  String get vcListenHint => 'Bosing va ayting: «chuqur o‘ra» yoki «o‘ra»';

  @override
  String get vcCloud => 'Serverni tekshirish';

  @override
  String get vcHeard => 'Eshitildi';

  @override
  String get vcEngine => 'Aniqladi';

  @override
  String get vcTime => 'Vaqt';

  @override
  String get vcLog => 'Jurnal';

  @override
  String get vcCopy => 'Jurnalni nusxalash';

  @override
  String get vcCopied => 'Jurnal nusxalandi';

  @override
  String get vcCommand => 'Buyruq';

  @override
  String get vcNone => 'buyruq topilmadi';

  @override
  String get vcError => 'Xato';

  @override
  String get vcWorking => 'Tinglayapman…';

  @override
  String get optMore => 'Boshqa variantlar';

  @override
  String get optLess => 'Yig‘ish';

  @override
  String get eventAskTitle => 'Bu nima edi?';

  @override
  String eventAgo(int speed, int sec) {
    return '$speed km/s · $sec s oldin';
  }

  @override
  String eventGuessHint(String name, int p) {
    return 'Ehtimol: $name · $p%';
  }

  @override
  String eventChosen(String name) {
    return 'Yozildi: $name';
  }

  @override
  String get eventViaVoice => 'ovoz bilan tanlandi';

  @override
  String get eventViaTap => 'bosib tanlandi';

  @override
  String get eventClose => 'Yopish';
}
