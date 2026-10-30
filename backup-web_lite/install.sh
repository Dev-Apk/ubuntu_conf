#!/bin/bash
set -e

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Ошибка: Требуются права root. Запустите: curl -fsSL ... | sudo bash"
  exit 1
fi

REPO="Dev-Apk/ubuntu_conf"
BRANCH="main"
DIR="backup-web_lite"
BASE_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}/${DIR}"
TARGET_DIR="/opt/stacks/${DIR}"

echo "📥 Скачивание файлов из репозитория..."
mkdir -p "${TARGET_DIR}"
cd "${TARGET_DIR}"

curl -fsSL "${BASE_URL}/backup.py" -o backup.py
curl -fsSL "${BASE_URL}/Dockerfile" -o Dockerfile
curl -fsSL "${BASE_URL}/compose.yaml" -o compose.yaml

echo "🔨 Остановка старых версий и сборка нового образа..."
docker compose down 2>/dev/null || true
docker compose up -d --build

SERVER_IP=$(hostname -I | awk '{print $1}')
echo "✅ Установка завершена!"
echo "🌐 Откройте в браузере: http://${SERVER_IP}:5000"
