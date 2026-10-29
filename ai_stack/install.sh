#!/bin/bash
set -e

# ============================================
# Проверка прав root
# ============================================
if [ "$EUID" -ne 0 ]; then
  echo "❌ Ошибка: Требуются права root."
  echo "Запустите так: curl -fsSL <URL> | sudo bash"
  exit 1
fi

echo "🚀 Начало установки AI Stack..."

# ============================================
# Проверка Docker
# ============================================
if ! command -v docker &> /dev/null; then
    echo "❌ Docker не установлен. Установите его командой:"
    echo "curl -fsSL https://raw.githubusercontent.com/Dev-Apk/ubuntu_conf/refs/heads/main/install-docker.sh | sudo bash"
    exit 1
fi

if ! docker compose version &> /dev/null; then
    echo "❌ Docker Compose не установлен."
    exit 1
fi

echo "✅ Docker и Docker Compose найдены."

# ============================================
# Определение UID/GID пользователя
# ============================================
TARGET_UID=${SUDO_UID:-1000}
TARGET_GID=${SUDO_GID:-1000}

INSTALL_DIR="/opt/stacks/ai_stack"

echo "📁 Создание структуры папок в $INSTALL_DIR..."
sudo mkdir -p "$INSTALL_DIR"/{config/nginx,data/{postgres,paperclip,freellmapi}}

# ============================================
# 1. Запись docker-compose.yml
# ============================================
echo "📝 Запись docker-compose.yml..."
sudo tee "$INSTALL_DIR/docker-compose.yml" > /dev/null << 'EOF'
services:
  # PostgreSQL 17 — база данных для Paperclip
  db:
    image: postgres:17-alpine
    container_name: paperclip_db
    environment:
      POSTGRES_USER: paperclip
      POSTGRES_PASSWORD: paperclip
      POSTGRES_DB: paperclip
    volumes:
      - /opt/stacks/ai_stack/data/postgres:/var/lib/postgresql/data
    networks:
      - app_network
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U paperclip"]
      interval: 5s
      timeout: 5s
      retries: 5

  # Paperclip (режим private)
  paperclip:
    image: ghcr.io/paperclipai/paperclip:latest
    container_name: paperclip_service
    depends_on:
      db:
        condition: service_healthy
    environment:
      HOST: 0.0.0.0
      PORT: 3100
      PAPERCLIP_HOME: /paperclip
      PAPERCLIP_DEPLOYMENT_MODE: private
      DATABASE_URL: postgres://paperclip:paperclip@db:5432/paperclip
      BETTER_AUTH_SECRET: local-dev-secret-key-123
    volumes:
      - /opt/stacks/ai_stack/data/paperclip:/paperclip
    networks:
      - app_network
    restart: unless-stopped
    stop_grace_period: 90s

  # FreeLLMAPI
  freellmapi:
    image: ghcr.io/tashfeenahmed/freellmapi:latest
    container_name: freellm_service
    env_file:
      - /opt/stacks/ai_stack/.env
    environment:
      PORT: 3001
      HOST_BIND: 0.0.0.0
    volumes:
      - /opt/stacks/ai_stack/data/freellmapi:/app/server/data
    networks:
      - app_network
    restart: unless-stopped

  # Nginx — обратный прокси
  nginx:
    image: nginx:alpine
    container_name: nginx_proxy
    ports:
      - "8080:80"
    volumes:
      - /opt/stacks/ai_stack/config/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
    depends_on:
      - paperclip
      - freellmapi
    networks:
      - app_network
    restart: unless-stopped

networks:
  app_network:
    driver: bridge
EOF

# ============================================
# 2. Запись nginx.conf
# ============================================
echo " Запись nginx.conf..."
sudo tee "$INSTALL_DIR/config/nginx/nginx.conf" > /dev/null << 'EOF'
events { worker_connections 1024; }
http {
    resolver 127.0.0.11 valid=30s;
    server {
        listen 80;
        server_name _;
        location / {
            proxy_pass http://paperclip:3100;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
        }
        location /api/ {
            rewrite ^/api/(.*) /$1 break;
            proxy_pass http://freellmapi:3001;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
    }
}
EOF

# ============================================
# 3. Генерация .env с ключом шифрования
# ============================================
echo "🔑 Генерация ENCRYPTION_KEY для FreeLLMAPI..."
ENCRYPTION_KEY=$(openssl rand -hex 32)
sudo echo "ENCRYPTION_KEY=$ENCRYPTION_KEY" | sudo tee "$INSTALL_DIR/.env" > /dev/null
echo "✅ Ключ сохранён в $INSTALL_DIR/.env"

# ============================================
# 4. Исправление прав доступа
# ============================================
echo "🔧 Исправление прав доступа..."
sudo chown -R $TARGET_UID:$TARGET_GID /opt/stacks

# ============================================
# 5. Первый запуск стека
# ============================================
echo "🚀 Запуск AI Stack..."
cd "$INSTALL_DIR"
sudo docker compose up -d

# ============================================
# 6. Вывод информации
# ============================================
echo ""
echo "✅ Установка завершена!"
echo ""
echo "🌐 Доступ к сервисам:"
echo "   Paperclip:           http://$(hostname -I | awk '{print $1}'):8080/"
echo "   FreeLLMAPI:          http://$(hostname -I | awk '{print $1}'):8080/api/"
echo "   FreeLLMAPI Dashboard: http://$(hostname -I | awk '{print $1}'):3001"
echo ""
echo "📂 Все данные находятся в: $INSTALL_DIR"
echo ""
echo "💡 Для установки Dockge (веб-управления) выполните:"
echo "   sudo mkdir -p /opt/stacks/dockge"
echo "   cd /opt/stacks/dockge"
echo "   sudo nano docker-compose.yml  # (вставьте конфиг Dockge)"
echo "   sudo docker compose up -d"
echo ""
echo "📋 Управление стеком:"
echo "   cd $INSTALL_DIR"
echo "   sudo docker compose up -d      # Запуск"
echo "   sudo docker compose down       # Остановка"
echo "   sudo docker compose logs -f    # Просмотр логов"
echo "   sudo docker compose ps         # Статус"
