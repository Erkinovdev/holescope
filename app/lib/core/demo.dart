/// ДЕМО-ДАННЫЕ ИЗ МАКЕТОВ FIGMA. Не реальные измерения.
/// TODO(этап 2/3): заменить на данные API (`/map/clusters`, `/drive/ahead`, `/trips`, рейтинги) и локальную БД.
/// Все экраны, которые читают отсюда, показывают плашку DemoBanner.
class Demo {
  static const potholeStreet = 'ул. Навои, 24';
  static const potholeDistanceM = 120;
  static const potholeDrivers = 7;
  static const potholeDaysAgo = 3;

  static const myFinds = [
    ('ул. Навои, 24', 'Глубокая яма · ×7', '120 м'),
    ('пр. Амира Темура, 108', 'Мелкая яма · ×1', '2,1 км'),
  ];

  static const streets = [
    ('ул. Бабура', 14.2),
    ('Кичик халка йули', 11.8),
    ('ул. Беруни', 9.4),
    ('пр. Мустакиллик', 7.1),
    ('ул. Нукус', 5.6),
  ];

  static const districts = [('Юнусабад', 78), ('Мирзо-Улугбек', 66), ('Чиланзар', 51), ('Сергели', 38)];

  static const notifications = [
    (0, 'Заделана: ул. Навои, 24', 'Подтверждено 3 водителями', '2 ч'),
    (1, 'Яма на вашем маршруте', 'пр. Амира Темура, 108', '5 ч'),
    (2, 'Жалоба принята', 'Xalq Nazorati · №48217', '1 д'),
    (3, 'Ваш вклад', '+12 подтверждений за неделю', '2 д'),
  ];

  static const topDrivers = [('Быстрый Беркут #0317', 412), ('Тихий Сокол #4821', 342), ('Ночной Барс #2209', 298)];

  static const profileName = 'Тихий Сокол #4821';
  static const profileStats = (128, 342, 1460);
  static const cityScore = 62;
  static const challengeDone = 128, challengeGoal = 200;
  static const weeklyFixed = 31, weeklyFound = 128, weeklyComplaints = 47;
  static const complaintNumber = '№48217';
  static const routeFast = (58, '18 мин · 9 ям');
  static const routeSmooth = (91, '21 мин · 2 ямы');
  static const speedKmh = 54, tripKm = 7.2, tripFound = 4;
}
