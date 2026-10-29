#!/bin/bash
set -e

# 1. Проверка прав root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Ошибка: Требуются права root."
  echo "Запустите так: curl -fsSL <URL> | sudo bash"
  exit 1
fi

echo "⏳ Начало установки Docker..."

# 2. Удаление устаревших версий (конфликтующих пакетов)
echo "🧹 Удаление устаревших пакетов Docker (если есть)..."
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
  apt-get remove -y "$pkg" || true
done

# 3. Обновление и установка зависимостей
echo "📦 Обновление пакетной базы и установка зависимостей..."
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release

# 4. Добавление официального GPG-ключа Docker
echo "🔑 Добавление GPG-ключа Docker..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# 5. Подключение репозитория Docker
echo "🔗 Подключение официального репозитория Docker..."
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Fallback: если репозиторий ещё не поддерживает новую версию Ubuntu (например, 26.04), используем 24.04 (noble)
if ! apt-get update -y >/dev/null 2>&1; then
  echo "⚠️ Репозиторий не поддерживает текущую версию Ubuntu. Используем noble (24.04) как fallback..."
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu noble stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
  apt-get update -y
fi

# 6. Установка Docker Engine и Compose
echo "🐳 Установка Docker Engine, containerd и Docker Compose..."
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 7. Запуск и автозапуск службы
echo "⚙️ Включение и запуск службы Docker..."
systemctl enable docker
systemctl start docker

# 8. Добавление пользователя в группу docker (для работы без sudo)
TARGET_USER=${SUDO_USER:-$USER}
if [ "$TARGET_USER" != "root" ]; then
  echo "👤 Добавление пользователя '$TARGET_USER' в группу docker..."
  usermod -aG docker "$TARGET_USER"
  echo "✅ Пользователь '$TARGET_USER' добавлен в группу docker."
  echo "💡 Чтобы изменения вступили в силу без перезагрузки, выполните: newgrp docker"
else
  echo "⚠️ Запуск от имени root. Группа docker не модифицировалась."
fi

# 9. Финальная проверка
echo "🧪 Проверка установки демона Docker..."
if docker run --rm hello-world >/dev/null 2>&1; then
  echo "✅ Docker успешно установлен и работает!"
else
  echo "⚠️ Docker установлен, но тестовый запуск не удался. Проверьте: systemctl status docker"
fi

echo "🎉 Готово! Для проверки выполните: docker --version и docker compose version"
