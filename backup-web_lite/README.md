# 🗄️ Backup Web Lite

Минималистичный веб-интерфейс для создания бэкапов Linux-сервера. Один контейнер, один Python-файл, никаких внешних зависимостей.

## ✨ Возможности

- 📁 Выбор **любой** папки на сервере (вся ФС смонтирована как `/host`)
- 💾 Создание `.tar.gz` архивов с живым прогрессом (файлы, размер, время, лог)
- ⬇️ Скачивание бэкапов на локальный ПК
- ⬆️ Загрузка бэкапов с ПК обратно на сервер
- 🗑️ Удаление старых бэкапов
- 🚫 Без пароля и БД — идеально для LAN/SSH-туннеля

## 🚀 Установка без сборкой

compose.yaml

```yaml
services:
  backup-web:
    image: ghcr.io/dev-apk/backup-web-lite:latest
    container_name: backup_web_lite
    ports:
      - 5000:5000
    volumes:
      - /:/host:ro
      - /opt/backups:/host/opt/backups
    restart: unless-stopped
```

```bash
sudo docker compose up -d
```

## 🚀 Установка одной командой со сборкой

```bash
curl -fsSL https://raw.githubusercontent.com/Dev-Apk/ubuntu_conf/main/backup-web_lite/install.sh | sudo bash
```

Скрипт сам скачает файлы, соберёт образ и запустит контейнер. Откройте `http://IP_СЕРВЕРА:5000`.

## 📦 Файлы репозитория

| Файл | Назначение |
|---|---|
| `install.sh` | Скрипт автоматической установки |
| `Dockerfile` | Сборка на базе Alpine + Python 3 |
| `compose.yaml` | Конфиг запуска контейнера |
| `backup.py` | Весь код: веб-сервер, API, UI в одном файле |

## 🔧 Как работает

1. Контейнер монтирует всю ФС хоста в `/host` (только чтение).
2. Папка `/opt/backups` смонтирована с правами на запись.
3. Python запускает HTTP-сервер на порту `5000`.
4. Фоновый поток создаёт архив, а браузер опрашивает статус каждую секунду.

## 🛠️ Обслуживание

**Остановить:**
```bash
cd /opt/stacks/backup-web_lite && sudo docker compose down
```

**Запустить:**
```bash
cd /opt/stacks/backup-web_lite && sudo docker compose up -d
```

**Обновить из GitHub:**
```bash
curl -fsSL https://raw.githubusercontent.com/Dev-Apk/ubuntu_conf/main/backup-web_lite/install.sh | sudo bash
```

**Посмотреть логи:**
```bash
sudo docker logs backup_web_lite
```

## ⚠️ Безопасность

- Порт `5000` **не публикуйте в интернет** — используйте только в LAN или через SSH-туннель (`ssh -L 5000:localhost:5000 user@server`).
- Контейнер видит всю ФС на чтение — при компрометации порта злоумышленник сможет скачать любые файлы, кроме `/opt/backups` (запись только туда).
- Для продакшена рекомендуется добавить Basic Auth в `backup.py`.

## 📋 Системные требования

- Linux с установленным Docker и Docker Compose
- ~30 МБ места на диске (образ Alpine + Python)


### Как загрузить в репозиторий:

```bash
cd /opt/stacks/backup-web_lite
# Создайте файл README.md с содержимым выше, затем:
sudo git add README.md
sudo git commit -m "Add README for backup-web_lite"
sudo git push origin main
```

