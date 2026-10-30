#!/bin/bash
set -e

# ============================================
# 1. Проверка прав root
# ============================================
if [ "$EUID" -ne 0 ]; then
  echo "❌ Ошибка: Требуются права root."
  echo "Запустите так: sudo bash deploy-exact.sh"
  exit 1
fi

echo "🚀 Начало развертывания строго по предоставленному конфигу..."

# ============================================
# 2. Проверка Docker
# ============================================
if ! command -v docker &> /dev/null || ! docker compose version &> /dev/null; then
    echo "❌ Docker или Docker Compose не установлены."
    exit 1
fi

# ============================================
# 3. Переменные и создание структуры папок
# ============================================
TARGET_UID=${SUDO_UID:-1000}
TARGET_GID=${SUDO_GID:-1000}
STACKS_DIR="/opt/stacks"

echo "📁 Создание структуры папок..."
mkdir -p "$STACKS_DIR"/{dockge/data,freellmapi/data,nginx,paperclip/data,postgres/data}

# ============================================
# 4. Создание внешней сети (требуется конфигами)
# ============================================
echo "🌐 Создание сети global_network..."
docker network create global_network 2>/dev/null || echo "   (Сеть уже существует)"

# ============================================
# 5. Запись файлов строго по предоставленному тексту
# ============================================
echo "📝 Запись конфигурационных файлов..."

# --- dockge/compose.yaml ---
cat > "$STACKS_DIR/dockge/compose.yaml" << 'EOF'
services:
  dockge:
    image: louislam/dockge:1
    restart: unless-stopped
    ports:
      # Host Port : Container Port
      - 5001:5001
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./data:/app/data
      # If you want to use private registries, you need to share the auth file with Dockge:
      # - /root/.docker/:/root/.docker

      # Stacks Directory
      # ⚠️ READ IT CAREFULLY. If you did it wrong, your data could end up writing into a WRONG PATH.
      # ⚠️ 1. FULL path only. No relative path (MUST)
      # ⚠️ 2. Left Stacks Path === Right Stacks Path (MUST)
      - /opt/stacks:/opt/stacks
    environment:
      # Tell Dockge where is your stacks directory
      - DOCKGE_STACKS_DIR=/opt/stacks
      - DOCKGE_ENABLE_CONSOLE=true
networks: {}
EOF

# --- freellmapi/compose.yaml ---
cat > "$STACKS_DIR/freellmapi/compose.yaml" << 'EOF'
services:
  freellmapi:
    image: ghcr.io/tashfeenahmed/freellmapi:latest
    container_name: freellm_service
    env_file:
      - .env
    environment:
      NODE_ENV: production
      PORT: 3001
      HOST_BIND: 0.0.0.0
    ports:
      - 3001:3001
    volumes:
      - ./data:/app/server/data
    restart: unless-stopped
    healthcheck:
      test:
        - CMD
        - node
        - -e
        - fetch('http://127.0.0.1:3001/api/ping').then((res) => { if (!res.ok)
          process.exit(1); }).catch(() => process.exit(1));
      interval: 30s
      timeout: 5s
      retries: 3
networks: {}
EOF

# --- freellmapi/.env (Генерация, так как файл указан в дереве, но необходим для запуска) ---
if [ ! -f "$STACKS_DIR/freellmapi/.env" ]; then
    echo "ENCRYPTION_KEY=$(openssl rand -hex 32)" > "$STACKS_DIR/freellmapi/.env"
fi

# --- nginx/docker-compose.yml ---
cat > "$STACKS_DIR/nginx/docker-compose.yml" << 'EOF'
services:
  nginx:
    image: nginx:alpine
    container_name: nginx_proxy
    ports:
      - 8080:80
    volumes:
      - /opt/stacks/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
    networks:
      - global_network
    restart: unless-stopped
    extra_hosts:
      - host.docker.internal:host-gateway
networks:
  global_network:
    external: true
EOF

# --- nginx/nginx.conf ---
cat > "$STACKS_DIR/nginx/nginx.conf" << 'EOF'
events { worker_connections 1024; }
http {
    resolver 127.0.0.11 valid=30s;
    server {
        listen 80;
        server_name _;

        # Прямое обращение к контейнеру paperclip в той же сети
        location / {
            proxy_pass http://paperclip_service:3100;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
        }
    }
}
EOF

# --- paperclip/docker-compose.yml ---
cat > "$STACKS_DIR/paperclip/docker-compose.yml" << 'EOF'
services:
  paperclip:
    image: ghcr.io/paperclipai/paperclip:latest
    container_name: paperclip_service
    environment:
      HOST: 0.0.0.0
      PORT: 3100
      PAPERCLIP_HOME: /paperclip
      PAPERCLIP_DEPLOYMENT_MODE: authenticated
      PAPERCLIP_DEPLOYMENT_EXPOSURE: private
      PAPERCLIP_PUBLIC_URL: http://127.0.0.1:3100
      BETTER_AUTH_SECRET: super-secret-key-for-local-dev-12345
      PAPERCLIP_TOOL_ACTION_SIGNING_SECRET: another-secret-key-for-tools-67890
      DATABASE_URL: postgres://paperclip:paperclip@paperclip_db:5432/paperclip
    ports:
      - 3100:3100
    volumes:
      - /opt/stacks/paperclip/data:/paperclip
    networks:
      - global_network
    restart: unless-stopped
    stop_grace_period: 90s
networks:
  global_network:
    external: true
EOF

# --- postgres/docker-compose.yml ---
cat > "$STACKS_DIR/postgres/docker-compose.yml" << 'EOF'
services:
  db:
    image: postgres:17-alpine
    container_name: paperclip_db
    environment:
      POSTGRES_USER: paperclip
      POSTGRES_PASSWORD: paperclip
      POSTGRES_DB: paperclip
    volumes:
      - /opt/stacks/postgres/data:/var/lib/postgresql/data
    networks:
      - global_network
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U paperclip"]
      interval: 5s
      timeout: 5s
      retries: 5

networks:
  global_network:
    external: true
EOF

# ============================================
# 6. Настройка прав доступа
# ============================================
echo "🔧 Настройка прав доступа..."
chown -R $TARGET_UID:$TARGET_GID "$STACKS_DIR"

# ============================================
# 7. Запуск стеков
# ============================================
echo "🚀 Запуск сервисов..."

echo "   [1/5] Запуск PostgreSQL..."
cd "$STACKS_DIR/postgres" && docker compose up -d

echo "   [2/5] Запуск Paperclip..."
cd "$STACKS_DIR/paperclip" && docker compose up -d

echo "   [3/5] Запуск Nginx..."
cd "$STACKS_DIR/nginx" && docker compose up -d

echo "   [4/5] Запуск FreeLLMAPI..."
cd "$STACKS_DIR/freellmapi" && docker compose up -d

echo "   [5/5] Запуск Dockge..."
cd "$STACKS_DIR/dockge" && docker compose up -d

# ============================================
# 8. Итог
# ============================================
SERVER_IP=$(hostname -I | awk '{print $1}')
echo ""
echo "✅ Развертывание завершено строго по конфигу!"
echo ""
echo "🌐 Доступные порты:"
echo "   Nginx (Paperclip): http://$SERVER_IP:8080/"
echo "   Paperclip (прямой): http://$SERVER_IP:3100/"
echo "   FreeLLMAPI:        http://$SERVER_IP:3001/"
echo "   Dockge:            http://$SERVER_IP:5001/"
