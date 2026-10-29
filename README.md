# ubuntu_conf

Набор безопасных Bash-скриптов для быстрой и автоматизированной настройки пользователей и прав доступа в операционных системах семейства Ubuntu/Debian.

## 🚀 Возможности

- ✅ Интерактивный ввод данных (защита от ошибок при копировании через `curl | bash`).
- ✅ Встроенные проверки: наличие прав root, существование пользователя, валидация синтаксиса `sudoers`.
- ✅ Создание домашней директории и корректная настройка окружения.

---

## 📜 Доступные скрипты

### 1. Создание пользователя с правами sudo (`addusersudo.sh`)
Скрипт запрашивает логин нового пользователя и пароль (с обязательным подтверждением). Затем он создает пользователя, задает пароль и добавляет его в группу `sudo`.

**Команда для запуска:**
```bash
curl -fsSL https://raw.githubusercontent.com/Dev-Apk/ubuntu_conf/refs/heads/main/addusersudo.sh | sudo bash
```

### 2. Включение sudo без пароля (`sudo-nopass.sh`)
Скрипт запрашивает логин уже существующего пользователя и настраивает выполнение команд через `sudo` без запроса пароля. Использует безопасный метод через отдельный файл с обязательной проверкой синтаксиса через `visudo`.

**Команда для запуска:**
```bash
curl -fsSL https://raw.githubusercontent.com/Dev-Apk/ubuntu_conf/refs/heads/main/sudo-nopass.sh | sudo bash
```


### 3. Установка Docker и Docker Compose (`install-docker.sh`)
Скрипт полностью автоматизирует установку официального Docker Engine и Docker Compose плагина. Он удаляет конфликтующие старые версии, добавляет официальный репозиторий, настраивает автозапуск и добавляет текущего пользователя в группу `docker` для работы без `sudo`.

**Команда для запуска:**
```bash
curl -fsSL https://raw.githubusercontent.com/Dev-Apk/ubuntu_conf/refs/heads/main/install-docker.sh | sudo bash
```


### 4. Установка AI Stack (Paperclip + FreeLLMAPI + Nginx + Dockge)

Полный стек для работы с AI-агентами: Paperclip (без аутентификации), FreeLLMAPI, PostgreSQL, Nginx и Dockge для управления. Устанавливается одной командой в `/opt/ai_stack`.

**Команда для запуска:**
```bash
curl -fsSL https://raw.githubusercontent.com/Dev-Apk/ubuntu_conf/refs/heads/main/ai_stack/install.sh | sudo bash
```


sudo /opt/ai_stack/scripts/start.sh    # Запуск
sudo /opt/ai_stack/scripts/stop.sh     # Остановка
sudo /opt/ai_stack/scripts/status.sh   # Статус
sudo /opt/ai_stack/scripts/backup.sh   # Бэкап

