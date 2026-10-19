"""Единый справочник «что это было»: варианты ответа водителя, разметки в админке и голосовых отметок.

Одна запись = метка (key), группа, названия ru/uz, тип объекта на карте и уровень. Все остальные части (вопросы в приложении, админка,
обучение, голосовые команды) берут варианты отсюда: добавить вариант — значит добавить строку ниже.
"""
from __future__ import annotations
from dataclasses import dataclass


@dataclass(frozen=True)
class Item:
    key: str
    group: str            # holes | humps | manholes | rails | surface | other
    ru: str
    uz: str
    road: bool = True     # True — дорожный объект (идёт на карту и в положительный класс модели), False — не дорога
    type: str = ""        # тип объекта на карте (EventCluster.type)
    level: str = ""       # light | mid | deep | danger
    driver: bool = True   # показывать водителю в опроснике
    hint_ru: str = ""     # пояснение в админке: как отличить


ITEMS: list[Item] = [
    # ── ямы по глубине
    Item("pothole_light", "holes", "Мелкая яма", "Sayoz o‘ra", type="pothole", level="light", hint_ru="Небольшая выбоина, ощущается как короткий стук"),
    Item("pothole_mid", "holes", "Яма средняя", "O‘rtacha o‘ra", type="pothole", level="mid", hint_ru="Заметный удар, машина «ныряет»"),
    Item("pothole_deep", "holes", "Глубокая яма", "Chuqur o‘ra", type="pothole", level="deep", hint_ru="Сильный удар, хочется затормозить"),
    Item("pothole_danger", "holes", "Опасная яма", "Xavfli o‘ra", type="pothole", level="danger", hint_ru="Может повредить колесо или подвеску"),
    Item("broken", "holes", "Разбитый участок (россыпь ям)", "Buzilgan qism (ko‘p o‘ralar)", type="broken", level="deep", hint_ru="Много ям подряд, объезжать неудобно"),
    Item("patch", "holes", "Заплатка (ямочный ремонт)", "Yamoq (ta’mirlangan joy)", type="patch", level="light", hint_ru="Неровная латка поверх ямы"),
    Item("crack", "holes", "Трещина / разлом", "Yoriq / darz", type="crack", level="light", hint_ru="Поперечная трещина или просадка кромки"),
    # ── искусственные неровности
    Item("bump_low", "humps", "Лежачий пологий", "Yotiq politsiyachi (past)", type="bump", level="light", hint_ru="Пологий «подиум» или плавная горка"),
    Item("bump", "humps", "Лежачий полицейский", "Yotiq politsiyachi", type="bump", level="mid", hint_ru="Обычный лежачий: два удара парой колёс"),
    Item("bump_high", "humps", "Лежачий крутой", "Yotiq politsiyachi (baland)", type="bump", level="deep", hint_ru="Высокий или резкий, без маркировки"),
    # ── люки
    Item("manhole", "manholes", "Люк", "Lyuk", type="manhole", level="light", hint_ru="Короткий одиночный стук на уровне полотна"),
    Item("manhole_sunk", "manholes", "Люк просел", "Lyuk cho‘kkan", type="manhole", level="mid", hint_ru="Люк ниже полотна, колесо проваливается"),
    Item("manhole_raised", "manholes", "Люк выступает", "Lyuk ko‘tarilib turibdi", type="manhole", level="mid", hint_ru="Люк выше полотна, колесо «подбрасывает»"),
    # ── рельсы, переезды, стыки
    Item("rail_tram", "rails", "Трамвайные рельсы", "Tramvay relslari", type="rail_tram", level="mid", hint_ru="Серия ударов под углом, на трамвайной линии"),
    Item("rail_train", "rails", "Ж/д переезд", "Temir yo‘l o‘tish joyi", type="rail_train", level="mid", hint_ru="Переезд через железную дорогу"),
    Item("joint", "rails", "Стык плит / шов", "Plita tutashuvi / chok", type="joint", level="light", hint_ru="Деформационный шов моста или стык плит"),
    # ── покрытие
    Item("washboard", "surface", "Волнистость (гребёнка)", "To‘lqinsimon yo‘l", type="rough_patch", level="mid", hint_ru="Частые ритмичные удары на протяжении десятков метров"),
    Item("rutting", "surface", "Колея", "Izlar (koleya)", type="rutting", level="mid", hint_ru="Продольные углубления от колёс"),
    Item("cobble", "surface", "Брусчатка / плитка", "Bruschatka / plitka", type="cobble", level="light", hint_ru="Мелкая вибрация на мощёном участке", driver=False),
    # ── не дорога
    Item("curb", "other", "Бордюр / съезд", "Bordyur / tushish joyi", road=False, hint_ru="Заезд на бордюр или в карман"),
    Item("braking", "other", "Резкое торможение / разгон", "Keskin tormozlash / tezlashish", road=False, driver=False, hint_ru="Продольный толчок без вертикального удара"),
    Item("handled", "other", "Телефон трогали / упал", "Telefonga tegildi / tushib ketdi", road=False, hint_ru="Одиночный сильный пик с поворотом телефона"),
    Item("noise", "other", "Ничего особенного", "Alohida narsa yo‘q", road=False, hint_ru="Шум дороги или двигателя"),
]

BY_KEY = {i.key: i for i in ITEMS}
# старые ключи и синонимы, которые могли прийти от прежних версий приложения
ALIASES = {"rail": "rail_tram", "nothing": "noise", "not_pothole": "noise"}
GROUPS = {
    "holes": ("Ямы и повреждения", "O‘ralar va shikastlar"),
    "humps": ("Лежачие полицейские", "Yotiq politsiyachilar"),
    "manholes": ("Люки", "Lyuklar"),
    "rails": ("Рельсы, переезды, стыки", "Relslar, o‘tish joylari, choklar"),
    "surface": ("Покрытие", "Qoplama"),
    "other": ("Не дорога", "Yo‘l emas"),
}

# Оценка ровности дороги (участок ≈ 200 м): классы совпадают с индексом ровности A–E.
ROAD_RATINGS = {
    "road_a": ("A", "Ровная", "Tekis"),
    "road_b": ("B", "Хорошая", "Yaxshi"),
    "road_c": ("C", "Удовлетворительная", "Qoniqarli"),
    "road_d": ("D", "Плохая", "Yomon"),
    "road_e": ("E", "Разбитая", "Buzilgan"),
}

LABEL_KEYS = [i.key for i in ITEMS]
ROAD_KEYS = {i.key for i in ITEMS if i.road}
# все допустимые значения «метки» события (включая устаревшие)
ACCEPTED = set(LABEL_KEYS) | set(ALIASES) | {"not_sure"}


def norm(key: str) -> str:
    """Старые ключи → текущие; неизвестные возвращаются как есть."""
    return ALIASES.get(key, key)


def is_road(key: str) -> bool:
    it = BY_KEY.get(norm(key))
    return bool(it and it.road)


def type_for(key: str) -> str:
    it = BY_KEY.get(norm(key))
    return it.type if it else ""


def level_for(key: str) -> str:
    it = BY_KEY.get(norm(key))
    return it.level if it else ""


def driver_options() -> list[str]:
    """Что предлагаем водителю после поездки: главное первым (то, что чаще), затем «ещё», в конце — «не знаю»."""
    main = ["pothole_light", "pothole_mid", "pothole_deep", "bump", "manhole", "rail_tram"]
    rest = [i.key for i in ITEMS if i.driver and i.key not in main and i.key not in ("noise",)]
    return main + rest + ["noise", "not_sure"]


def as_json() -> dict:
    """Для приложения и админки: список вариантов с названиями и группами."""
    return dict(
        items=[dict(key=i.key, group=i.group, ru=i.ru, uz=i.uz, road=i.road, type=i.type, level=i.level, driver=i.driver, hint=i.hint_ru) for i in ITEMS],
        groups={k: dict(ru=v[0], uz=v[1]) for k, v in GROUPS.items()},
        road_ratings={k: dict(cls=v[0], ru=v[1], uz=v[2]) for k, v in ROAD_RATINGS.items()},
        driver_options=driver_options(),
        extra={"not_sure": dict(ru="Не знаю", uz="Bilmayman")},
    )
