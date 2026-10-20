# Векторные тайлы карты Ташкента

Тайлы не лежат в git (`site/map/t/`, ~17 МБ). Сборка (planetiler, нужен backend/data/uzbekistan.osm.pbf):

```
docker run --rm -v <data>:/data -v <out>:/out -e JAVA_TOOL_OPTIONS=-Xmx3g ghcr.io/onthegomap/planetiler:latest \
  --osm-path=/data/uz.osm.pbf --download --bounds=69.05,41.15,69.50,41.45 \
  --output=/out/t --output-format=files --force --maxzoom=14 --tmpdir=/data/tmp
```

Океанские полигоны (water-polygons-split-3857.zip, ~1 ГБ) Ташкенту не нужны: в data/sources кладётся пустая заглушка с этим именем, чтобы не качать.

Загрузка на сервер: `(cd site/map && tar -czf - t) | ssh root@HOST 'tar -xzf - -C /opt/holescope/site/map'`.
Стили: `python tools/make_map_style.py` → site/map/style-{dark,light}.json. Шрифты подписей — site/map/fonts (Noto Sans, protomaps/basemaps-assets).
