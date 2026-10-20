# Готовые сборки · версия 2.1.0 (сборка 21)

| Файл | Для чего | Пакет |
|---|---|---|
| `holescope.apk` | Телефон Android (7.0 и новее) | `uz.holescope.holescope` |
| `holescope-monitor.apk` | **Штатный монитор автомобиля** (Android 9, широкий экран, например Geely Geometry E). Это отдельное приложение «Holescope Монитор»: горизонтальный экран, крупные кнопки, ночная тема, экран не гаснет | `uz.holescope.holescope.monitor` |
| `holescope.ipa` | iPhone, без подписи (собирается на GitHub Actions только по слову «IPA»; версия 2.1.0) | — |

Обе Android-сборки можно ставить на одно устройство одновременно: у них разные пакеты.

## Как собирали

```
# телефон
flutter build apk --release --dart-define=API_BASE=https://holescop.duckdns.org

# монитор
HOLESCOPE_MONITOR=1 flutter build apk --release --dart-define=API_BASE=https://holescop.duckdns.org --dart-define=CAR_MONITOR=true
```

Монитор: если в головном устройстве нет датчика ускорения, запись ударов работать не будет — останутся карта, предупреждения о ямах (по GPS) и ответы на вопросы.
