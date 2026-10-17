#!/usr/bin/env python3
"""Holescope: алгоритм v1 (правила). Находит толчки, отбрасывает удары по телефону, ставит уровень ямы.

Запуск:
    python analysis\detect.py analysis\запись.csv
    python analysis\detect.py analysis\запись.csv --labels analysis\labels_запись.json   # сверка с вашей разметкой
Правила (v1, по одной поездке — ориентировочные):
  1. Толчок: пик > max(2.0, 4 × фоновый шум за 20 с), скорость от 3,6 км/ч.
  2. «Касание»: резкий одиночный пик (второго удара нет pair<0.2, длительность <250 мс, пик >6) — это не дорога.
  3. Остальное — «яма/неровность». Уровень по энергии удара: <2.2 лёгкая, 2.2–5 средняя, ≥5 глубокая.
"""
from __future__ import annotations
import argparse, json, sys
from pathlib import Path
from collections import Counter
from review import build

def classify(e):
    if e["pair"] < 0.2 and e["dur"] < 250 and e["peak"] > 6:
        return "touch", None
    lvl = "light" if e["energy"] < 2.2 else "mid" if e["energy"] < 5 else "deep"
    return "pothole", lvl

def main():
    for s in (sys.stdout, sys.stderr):
        try: s.reconfigure(encoding="utf-8", errors="replace")
        except Exception: pass
    ap = argparse.ArgumentParser(); ap.add_argument("csv"); ap.add_argument("--labels")
    a = ap.parse_args()
    data, st = build(Path(a.csv), 2.0, 4.0, 1.0)
    ev = data["events"]
    pred = {e["id"]: classify(e) for e in ev}
    c = Counter(p[0] for p in pred.values())
    lv = Counter(p[1] for p in pred.values() if p[1])
    print(f"Событий: {len(ev)}; ям/неровностей: {c['pothole']} (лёгких {lv['light']}, средних {lv['mid']}, глубоких {lv['deep']}); касаний телефона: {c['touch']}")
    if a.labels:
        L = {x["id"]: x["label"] for x in json.load(open(a.labels, encoding="utf-8"))["labels"]}
        real = {"pothole_light", "pothole_mid", "pothole_deep"}
        flagged = [i for i, p in pred.items() if p[0] == "pothole" and i in L]
        tp = sum(L[i] in real for i in flagged)
        road = sum(L[i] in real | {"bump", "manhole"} for i in flagged)
        print(f"Сверка с разметкой ({len(L)} событий):")
        print(f"  названо ямой: {len(flagged)}; ямой оказалось: {tp} ({100*tp/max(len(flagged),1):.0f}%), "
              f"реальная неровность (яма/лежачий/люк): {road} ({100*road/max(len(flagged),1):.0f}%)")
        touch = [i for i, p in pred.items() if p[0] == "touch" and i in L]
        print(f"  отброшено как касание: {len(touch)}: " + ", ".join(L[i] for i in touch))
        ph = [i for i in flagged if L[i] in real]
        names = {"light": "pothole_light", "mid": "pothole_mid", "deep": "pothole_deep"}
        ex = sum(names[pred[i][1]] == L[i] for i in ph)
        print(f"  уровень совпал у {ex} из {len(ph)} ям ({100*ex/max(len(ph),1):.0f}%); для сравнения «всё лёгкая» даёт "
              f"{100*sum(L[i]=='pothole_light' for i in ph)/max(len(ph),1):.0f}%")
if __name__ == "__main__":
    main()
