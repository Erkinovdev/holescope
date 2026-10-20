#!/usr/bin/env bash
# Веб-версия приложения (для проверки на iPhone без установки): ./build_web.sh, затем ./deploy.sh root@95.217.220.168
# Открывается по адресу https://holescop.duckdns.org/app/
set -euo pipefail
cd "$(dirname "$0")/app"
MSYS_NO_PATHCONV=1 flutter build web --release --base-href /app/ --dart-define=API_BASE="${API_BASE:-https://holescop.duckdns.org}"
rm -rf ../webapp && cp -r build/web ../webapp
echo "готово: webapp/ ($(du -sh ../webapp | cut -f1))"
