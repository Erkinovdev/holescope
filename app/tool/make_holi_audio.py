"""Фразы помощницы «Холи»: единый источник текстов и генератор озвучки (edge-tts: ru-RU-SvetlanaNeural, uz-UZ-MadinaNeural).
Запуск: python tool/make_holi_audio.py  → assets/holi/holi_phrases.json и assets/holi/audio/<file>_<lang>.mp3"""
import asyncio, json, os, sys
import edge_tts

VOICES = {"ru": "ru-RU-SvetlanaNeural", "uz": "uz-UZ-MadinaNeural"}
DIST = {  # метры → как говорим
    50: ("пятьдесят", "ellik"), 100: ("сто", "yuz"), 150: ("сто пятьдесят", "yuz ellik"),
    200: ("двести", "ikki yuz"), 250: ("двести пятьдесят", "ikki yuz ellik"), 300: ("триста", "uch yuz"),
}
P = [  # key, ru, uz
    ("listening", "Холи слушает", "Xoli tinglayapti"),
    ("wake_yes", "Да?", "Ha?"),
    ("wake_listen", "Слушаю", "Tinglayapman"),
    ("mark_pothole", "Отметила яму", "O'ra belgilandi"),
    ("mark_deep", "Отметила глубокую яму", "Chuqur o'ra belgilandi"),
    ("mark_bump", "Отметила лежачий полицейский", "Yotiq politsiyachi belgilandi"),
    ("mark_manhole", "Отметила люк", "Lyuk belgilandi"),
    ("mark_cancel", "Убрала отметку", "Belgi o'chirildi"),
    ("mark_cancel_none", "Отменять нечего", "Bekor qiladigan narsa yo'q"),
    ("thanks", "Спасибо, записала", "Rahmat, yozib oldim"),
    ("ask_confirm", "Только что была яма? Скажите: да или нет", "Hozir o'ra bo'ldimi? Ha yoki yo'q deng"),
    ("confirm_yes", "Записала", "Yozib oldim"),
    ("confirm_no", "Хорошо, убрала", "Yaxshi, o'chirdim"),
    ("no_answer", "Не услышала, пропускаю", "Eshitmadim, o'tkazib yuboraman"),
    ("ahead_deep", "Впереди глубокая яма, снизьте скорость", "Oldinda chuqur o'ra, tezlikni kamaytiring"),
    ("ahead_bump", "Впереди лежачий полицейский", "Oldinda yotiq politsiyachi"),
    ("repeat", "Не расслышала, повторите", "Eshitmadim, takrorlang"),
    ("unknown", "Не поняла. Скажите: яма, люк или лежачий", "Tushunmadim. Ayting: o'ra, lyuk yoki yotiq politsiyachi"),
    ("km_smooth", "Последний километр ровный", "Oxirgi kilometr tekis"),
    ("km_rough", "Последний километр разбитый", "Oxirgi kilometr buzilgan"),
    ("trip_done", "Поездка записана. Хорошей дороги", "Safar yozildi. Yo'lingiz ravon bo'lsin"),
]
P += [
    ("err_mic", "Нет доступа к микрофону. Разрешите его в настройках", "Mikrofonga ruxsat yo'q. Sozlamalarda ruxsat bering"),
    ("err_speech", "Не получается включить распознавание речи", "Nutqni aniqlashni yoqib bo'lmadi"),
    ("err_net", "Нет связи с сервером, команду не услышала", "Server bilan aloqa yo'q, buyruqni eshitmadim"),
    ("ok_end", "Хорошо", "Yaxshi"),
    ("help", "Скажите: яма, глубокая яма, лежачий, люк, рельсы или переезд. Оценить дорогу: ровная, хорошая, плохая или разбитая. Чтобы убрать отметку, скажите: отмена",
     "Ayting: o'ra, chuqur o'ra, yotiq politsiyachi, lyuk, relslar yoki o'tish joyi. Yo'lni baholash: tekis, yaxshi, yomon yoki buzilgan. Belgini o'chirish uchun: bekor"),
    ("mark_not_pothole", "Понятно, это не яма", "Tushunarli, bu o'ra emas"),
]
# отметки по всем вариантам справочника сервера (backend/brain/taxonomy.py) и оценки дороги
import importlib.util
_spec = importlib.util.spec_from_file_location("taxonomy", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "backend", "brain", "taxonomy.py"))
_tx = importlib.util.module_from_spec(_spec); sys.modules["taxonomy"] = _tx; _spec.loader.exec_module(_tx)
_have = {k for k, _, _ in P}
for it in _tx.ITEMS:
    if f"mark_{it.key}" not in _have:
        P.append((f"mark_{it.key}", f"Отметила: {it.ru.lower()}", f"{it.uz} belgilandi"))
for k, (cls, ru, uz) in _tx.ROAD_RATINGS.items():
    P.append((f"rate_{k}", f"Дорога {ru.lower()}, записала", f"Yo'l {uz.lower()}, yozib oldim"))
for m, (ru, uz) in DIST.items():  # фразы с расстоянием: сервис подбирает ближайшее значение
    P.append((f"ahead_pothole_{m}", f"Впереди яма, {ru} метров" if m not in (100,) else "Впереди яма, сто метров", f"Oldinda o'ra, {uz} metr"))
    P.append((f"ahead_rough_{m}", f"Впереди разбитый участок, {ru} метров", f"Oldinda yo'l buzilgan, {uz} metr"))


async def one(text, voice, path):
    await edge_tts.Communicate(text, voice, rate="+5%").save(path)


async def main():
    out = os.path.join("assets", "holi")
    os.makedirs(os.path.join(out, "audio"), exist_ok=True)
    items = [dict(key=k, ru=ru, uz=uz, file=k) for k, ru, uz in P]
    json.dump(items, open(os.path.join(out, "holi_phrases.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    for it in items:
        for lang, voice in VOICES.items():
            path = os.path.join(out, "audio", f"{it['file']}_{lang}.mp3")
            if os.path.exists(path) and "--force" not in sys.argv:
                continue
            for attempt in range(3):
                try:
                    await one(it[lang], voice, path); break
                except Exception as e:
                    if attempt == 2: raise
                    await asyncio.sleep(2)
    print(len(items), "phrases")

asyncio.run(main())
