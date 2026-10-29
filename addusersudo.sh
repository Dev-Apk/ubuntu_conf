#!/bin/bash
set -e

# 1. Проверка прав root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Ошибка: Требуются права root."
  echo "Запустите так: curl -fsSL <URL> | sudo bash"
  exit 1
fi

# 2. Запрос логина (строго с клавиатуры)
read -p "Логин нового пользователя: " USER < /dev/tty

# 3. Проверка существования
if id "$USER" &>/dev/null; then
    echo "❌ Ошибка: Пользователь '$USER' уже существует."
    exit 1
fi

# 4. Запрос пароля с проверкой
while true; do
    read -s -p "Пароль: " PASS < /dev/tty
    echo
    read -s -p "Повторите пароль: " PASS2 < /dev/tty
    echo
    if [ "$PASS" = "$PASS2" ] && [ -n "$PASS" ]; then
        break
    else
        echo "⚠️ Пароли не совпадают или пусты, попробуйте снова."
    fi
done

# 5. Создание и настройка
echo "⏳ Создание пользователя $USER..."
adduser --disabled-password --gecos "" "$USER"
echo "$USER:$PASS" | chpasswd
usermod -aG sudo "$USER"

echo "✅ Готово! Пользователь '$USER' создан и добавлен в sudo."
