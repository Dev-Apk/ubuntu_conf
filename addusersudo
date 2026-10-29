#!/bin/bash
set -e

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Ошибка: Требуются права root."
  echo "Запустите так: curl -fsSL <URL> | sudo bash"
  exit 1
fi

read -p "Логин нового пользователя: " USER

# Проверка существования
if id "$USER" &>/dev/null; then
    echo "❌ Ошибка: Пользователь '$USER' уже существует."
    exit 1
fi

while true; do
    read -s -p "Пароль: " PASS
    echo
    read -s -p "Повторите пароль: " PASS2
    echo
    if [ "$PASS" = "$PASS2" ] && [ -n "$PASS" ]; then
        break
    else
        echo "⚠️ Пароли не совпадают или пусты, попробуйте снова."
    fi
done

echo "⏳ Создание пользователя $USER..."
adduser --disabled-password --gecos "" "$USER"
echo "$USER:$PASS" | chpasswd
usermod -aG sudo "$USER"

echo "✅ Готово! Пользователь '$USER' создан и добавлен в sudo."
