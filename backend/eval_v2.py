import json, sys, collections
import numpy as np
from holescope_algo.pipeline import process_csv
from holescope_algo.params import Params
A = "../analysis/"
def run(name, wb=2.485):
    p = Params(wheelbase_m=wb)
    r = process_csv(A + name, p)
    return r
for name in ["pothole_2026-10-16_18-14-37.csv", "pothole_2026-10-17_12-09-50.csv"]:
    r = run(name)
    ev = r["events"]
    types = collections.Counter(e["type"] for e in ev); lv = collections.Counter(e["level"] for e in ev if e["level"])
    seg = r["segments"]
    print("==", name)
    print(" ось вперёд определена:", r["fwd_axis_ok"], "| «в руке» интервалов:", len(r["hand_segments"]), [(round(a),round(b)) for a,b in r["hand_segments"]][:6])
    print(" событий:", len(ev), dict(types), "уровни:", dict(lv))
    print(" авто-поездки (старт-стоп, с):", [(round(a), round(b)) for a, b in r["auto_trips"]], "длительность", round(r["duration_s"]))
    print(" ровность A..E:", {c: int((seg.cls == c).sum()) for c in "ABCDE"}, "сегментов", len(seg))
    print(" подвеска:", r["damping"], r["suspension"])
    if "10-16" in name:
        L = {x["t"]: x["label"] for x in json.load(open(A + "labels_pothole_2026-10-16_18-14-37.json", encoding="utf-8"))["labels"]}
        lt = np.array(list(L.keys())); lab = list(L.values())
        rows = []
        for e in ev:
            k = int(np.argmin(np.abs(lt - e["t"])))
            if abs(lt[k] - e["t"]) < 0.6: rows.append((e, lab[k]))
        print(" сопоставлено с разметкой:", len(rows), "из", len(L))
        real = {"pothole_light", "pothole_mid", "pothole_deep", "bump", "manhole"}
        tp = sum(1 for e, l in rows if e["type"] in ("pothole", "bump", "manhole") and l in real)
        fp = sum(1 for e, l in rows if e["type"] in ("pothole", "bump", "manhole") and l not in real)
        fn = sum(1 for e, l in rows if e["type"] in ("noise", "touch") and l in real)
        tn = sum(1 for e, l in rows if e["type"] in ("noise", "touch") and l not in real)
        print(f" дорога/не дорога: TP {tp} FP {fp} FN {fn} TN {tn}; точность {tp/max(tp+fp,1):.0%}, полнота {tp/max(tp+fn,1):.0%}")
        ph = [(e, l) for e, l in rows if l.startswith("pothole")]
        nm = {"light": "pothole_light", "mid": "pothole_mid", "deep": "pothole_deep", "danger": "pothole_deep"}
        ok = sum(1 for e, l in ph if e["level"] and nm[e["level"]] == l)
        base = sum(1 for e, l in ph if l == "pothole_light")
        print(f" уровень яма: совпал {ok}/{len(ph)} = {ok/max(len(ph),1):.0%}; «всё лёгкая» даёт {base/max(len(ph),1):.0%}")
        conf = collections.Counter((l, e["type"]) for e, l in rows); print(" разметка×тип:", dict(conf))
        # признаки по группам
        import statistics as st
        for g in ("pothole_light","pothole_mid","pothole_deep","noise","handled"):
            xs = [e for e, l in rows if l == g]
            if xs: print(f"  {g:13s} n={len(xs):2d} score med {st.median(e['score'] for e in xs):5.2f} ratio {st.median(e['ratio'] for e in xs):5.1f} pair {st.median(e['pair'] for e in xs):.2f} gyro {st.median(e['gyro_peak'] for e in xs):6.1f} dur {st.median(e['dur_ms'] for e in xs):5.0f} speed {st.median(e['speed_kmh'] for e in xs):4.0f}")
