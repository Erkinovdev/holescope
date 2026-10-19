"""Иконки приложения из фирменного знака (assets/figma/logo.svg): Android (legacy + adaptive) и iOS. Запуск: python tool/make_icons.py"""
import json, os
from PIL import Image, ImageDraw

BG, AMBER = (11, 13, 18), (255, 176, 32)
S = 8  # суперсэмплинг


def logo(size, bg=True):
    """Знак (прицел + яма) на квадрате size×size; без фона — прозрачный."""
    n = size * S
    im = Image.new("RGBA", (n, n), BG + (255,) if bg else (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    u = n / 96.0
    def rr(x, y, w, h, r=3.36): d.rounded_rectangle([x * u, y * u, (x + w) * u, (y + h) * u], radius=r * u, fill=AMBER)
    d.ellipse([5.76 * u, 5.76 * u, 90.24 * u, 90.24 * u], outline=AMBER, width=int(6.72 * u))
    rr(44.64, 0, 6.72, 21.12); rr(44.64, 74.88, 6.72, 21.12); rr(0, 44.64, 21.12, 6.72); rr(74.88, 44.64, 21.12, 6.72)
    d.ellipse([(48 - 22.08) * u, (48 - 12.96) * u, (48 + 22.08) * u, (48 + 12.96) * u], fill=AMBER)
    d.ellipse([(48 - 14.4) * u, (50.4 - 7.2) * u, (48 + 14.4) * u, (50.4 + 7.2) * u], fill=BG + (255,))
    return im.resize((size, size), Image.LANCZOS)


def on_canvas(canvas, frac, bg):
    """Знак занимает долю frac стороны, по центру."""
    base = Image.new("RGBA", (canvas, canvas), BG + (255,) if bg else (0, 0, 0, 0))
    m = int(canvas * frac)
    mark = logo(m, bg=False)
    base.alpha_composite(mark, ((canvas - m) // 2, (canvas - m) // 2))
    return base


def save(im, path, opaque=False):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    (im.convert("RGB") if opaque else im).save(path)

# Android legacy
res = "android/app/src/main/res"
for dpi, px in dict(mdpi=48, hdpi=72, xhdpi=96, xxhdpi=144, xxxhdpi=192).items():
    save(on_canvas(px, 0.66, True), f"{res}/mipmap-{dpi}/ic_launcher.png")
# Android adaptive (108dp; безопасная зона ~66%)
for dpi, px in dict(mdpi=108, hdpi=162, xhdpi=216, xxhdpi=324, xxxhdpi=432).items():
    save(on_canvas(px, 0.5, False), f"{res}/mipmap-{dpi}/ic_launcher_foreground.png")
os.makedirs(f"{res}/mipmap-anydpi-v26", exist_ok=True)
open(f"{res}/mipmap-anydpi-v26/ic_launcher.xml", "w").write('<?xml version="1.0" encoding="utf-8"?>\n<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n    <background android:drawable="@color/ic_launcher_background"/>\n    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n</adaptive-icon>\n')
os.makedirs(f"{res}/values", exist_ok=True)
open(f"{res}/values/ic_launcher_background.xml", "w").write('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="ic_launcher_background">#0B0D12</color>\n</resources>\n')
# iOS (без альфа-канала)
ios = "ios/Runner/Assets.xcassets/AppIcon.appiconset"
for it in json.load(open(f"{ios}/Contents.json"))["images"]:
    w = float(it["size"].split("x")[0]) * int(it["scale"][0])
    save(on_canvas(int(round(w)), 0.7, True), f"{ios}/{it['filename']}", opaque=True)
save(on_canvas(1024, 0.7, True), "assets/icon_1024.png", opaque=True)
print("ok")
