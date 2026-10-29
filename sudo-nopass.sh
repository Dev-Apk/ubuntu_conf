#!/bin/bash
set -e

# 1. Проверка прав root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Ошибка: Требуются права root."
  echo "Запустите так: curl -fsSL <URL> | sudo bash"
  exit 1
fi

# 2. Запрос логина
read -p "Логин пользователя: " USER < /dev/tty

# 3. Проверка существования пользователя
if ! id "$USER" &>/dev/null; then
    echo "❌ Ошибка: Пользователь '$USER' не найден."
    exit 1
fi

SUDOERS_FILE="/etc/sudoers.d/$USER"

# 4. Применение настройки NOPASSWD
echo "⏳ Настройка sudo без пароля для $USER..."
echo "$USER ALL=(ALL) NOPASSWD: ALL" > "$SUDOERS_FILE"
chmod 0440 "$SUDOERS_FILE"

# 5. Проверка синтаксиса (безопасность)
if visudo -cf "$SUDOERS_FILE" &>/dev/null; then
    echo "✅ Готово! Пользователь '$USER' теперь может использовать sudo без пароля."
else
    echo "❌ Ошибка синтаксиса. Настройка отменена."
    rm -f "$SUDOERS_FILE"
    exit 1
fi
