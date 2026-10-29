#!/bin/bash
set -e

# ============================================
# 1. Проверка прав root
# ============================================
if [ "$EUID" -ne 0 ]; then
  echo "❌ Ошибка: Требуются права root."
  echo "Запустите так: curl -fsSL <URL> | sudo bash"
  exit 1
fi

echo "🚀 Начало установки AI Stack и Dockge..."

# ============================================
# 2. Проверка Docker
# ============================================
if ! command -v docker &> /dev/null || ! docker compose version &> /dev/null; then
    echo "❌ Docker или Docker Compose не установлены."
    echo "Сначала установите Docker: curl -fsSL https://raw.githubusercontent.com/Dev-Apk/ubuntu_conf/refs/heads/main/install-docker.sh | sudo bash"
    exit 1
fi

# ============================================
# 3. Определение UID/GID текущего пользователя
# ============================================
TARGET_UID=${SUDO_UID:-1000}
TARGET_GID=${SUDO_GID:-1000}

AI_STACK_DIR="/opt/stacks/ai_stack"
DOCKGE_DIR="/opt/stacks/dockge"

echo "📁 Создание структуры папок..."
mkdir -p "$AI_STACK_DIR"/{config/nginx,data/{postgres,paperclip,freellmapi}}
mkdir -p "$DOCKGE_DIR/data"

# ============================================
# 4. Генерация docker-compose.yml для AI Stack
# ============================================
echo "📝 Создание конфигурации AI Stack..."
cat > "$AI_STACK_DIR/docker-compose.yml" << EOF
services:
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
# 5. Создание nginx.conf (гарантированно как файл)
# ============================================
echo "📝 Создание nginx.conf..."
cat > "$AI_STACK_DIR/config/nginx/nginx.conf" << 'EOF'
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
# 6. Генерация .env для FreeLLMAPI
# ============================================
echo "🔑 Генерация ключа шифрования..."
echo "ENCRYPTION_KEY=$(openssl rand -hex 32)" > "$AI_STACK_DIR/.env"

# ============================================
# 7. Генерация docker-compose.yml для Dockge
# ============================================
echo "📝 Создание конфигурации Dockge..."
cat > "$DOCKGE_DIR/docker-compose.yml" << EOF
services:
  dockge:
    image: louislam/dockge:1
    container_name: dockge
    restart: unless-stopped
    ports:
      - "5001:5001"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /opt/stacks/dockge/data:/app/data
      - /opt/stacks:/opt/stacks
    environment:
      - DOCKGE_STACKS_DIR=/opt/stacks
      - PUID=$TARGET_UID
      - PGID=$TARGET_GID
EOF

# ============================================
# 8. Исправление прав доступа
# ============================================
echo "🔧 Настройка прав доступа..."
chown -R $TARGET_UID:$TARGET_GID /opt/stacks

# ============================================
# 9. Запуск всех сервисов
# ============================================
echo "🚀 Запуск Dockge..."
cd "$DOCKGE_DIR"
docker compose up -d

echo "🚀 Запуск AI Stack..."
cd "$AI_STACK_DIR"
docker compose up -d

# ============================================
# 10. Финальный вывод
# ============================================
SERVER_IP=$(hostname -I | awk '{print $1}')
echo ""
echo "✅ Установка успешно завершена!"
echo ""
echo "🌐 Веб-интерфейсы:"
echo "   Paperclip:           http://$SERVER_IP:8080/"
echo "   FreeLLMAPI Dashboard: http://$SERVER_IP:3001"
echo "   Dockge (Управление): http://$SERVER_IP:5001"
echo ""
echo "💡 Откройте Dockge. Стек 'ai_stack' уже будет там отображаться и управляться."
echo "📂 Все данные лежат в: /opt/stacks/"
