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
# Создание структуры папок
# ============================================
INSTALL_DIR="/opt/ai_stack"
echo "📁 Создание структуры в $INSTALL_DIR..."

mkdir -p "$INSTALL_DIR"/{config/nginx,data/{postgres,paperclip,freellmapi,dockge},stacks,scripts}

# ============================================
# Запись docker-compose.yml
# ============================================
echo "📝 Запись docker-compose.yml..."
cat > "$INSTALL_DIR/docker-compose.yml" << 'EOF'
services:
  db:
    image: postgres:17-alpine
    container_name: paperclip_db
    environment:
      POSTGRES_USER: paperclip
      POSTGRES_PASSWORD: paperclip
      POSTGRES_DB: paperclip
    volumes:
      - ./data/postgres:/var/lib/postgresql/data
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
      PAPERCLIP_DEPLOYMENT_MODE: local_trusted
      DATABASE_URL: postgres://paperclip:paperclip@db:5432/paperclip
    volumes:
      - ./data/paperclip:/paperclip
    networks:
      - app_network
    restart: unless-stopped
    stop_grace_period: 90s

  freellmapi:
    image: ghcr.io/tashfeenahmed/freellmapi:latest
    container_name: freellm_service
    env_file:
      - .env
    environment:
      PORT: 3001
      HOST_BIND: 0.0.0.0
    volumes:
      - ./data/freellmapi:/app/server/data
    networks:
      - app_network
    restart: unless-stopped

  nginx:
    image: nginx:alpine
    container_name: nginx_proxy
    ports:
      - "80:80"
    volumes:
      - ./config/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
    depends_on:
      - paperclip
      - freellmapi
    networks:
      - app_network
    restart: unless-stopped

  dockge:
    image: louislam/dockge:1
    container_name: dockge
    ports:
      - "5001:5001"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./stacks:/opt/stacks
      - ./data/dockge:/app/data
    environment:
      DOCKGE_STACKS_DIR: /opt/stacks
    networks:
      - app_network
    restart: unless-stopped

networks:
  app_network:
    driver: bridge
EOF

# ============================================
# Запись nginx.conf
# ============================================
echo "📝 Запись nginx.conf..."
cat > "$INSTALL_DIR/config/nginx/nginx.conf" << 'EOF'
events {
    worker_connections 1024;
}

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
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
        }

        location /api/ {
            rewrite ^/api/(.*) /$1 break;
            proxy_pass http://freellmapi:3001;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }
}
EOF

# ============================================
# Запись скриптов
# ============================================
echo "📝 Запись вспомогательных скриптов..."

cat > "$INSTALL_DIR/scripts/init.sh" << 'EOF'
#!/bin/bash
set -e
cd /opt/ai_stack

if [ ! -s .env ] || ! grep -q "ENCRYPTION_KEY=" .env; then
    echo "🔑 Генерация ENCRYPTION_KEY для FreeLLMAPI..."
    ENCRYPTION_KEY=$(openssl rand -hex 32)
    echo "ENCRYPTION_KEY=$ENCRYPTION_KEY" | tee .env > /dev/null
    echo "✅ Ключ сохранён в .env"
else
    echo "✅ .env уже существует с ENCRYPTION_KEY"
fi
EOF

cat > "$INSTALL_DIR/scripts/start.sh" << 'EOF'
#!/bin/bash
set -e
cd /opt/ai_stack

echo "🚀 Запуск всех сервисов..."
docker compose up -d
echo ""
echo "✅ Сервисы запущены. Статус:"
docker compose ps
EOF

cat > "$INSTALL_DIR/scripts/stop.sh" << 'EOF'
#!/bin/bash
set -e
cd /opt/ai_stack

echo "⏹️ Остановка всех сервисов..."
docker compose down
echo "✅ Все сервисы остановлены."
EOF

cat > "$INSTALL_DIR/scripts/status.sh" << 'EOF'
#!/bin/bash
cd /opt/ai_stack
docker compose ps
EOF

cat > "$INSTALL_DIR/scripts/backup.sh" << 'EOF'
#!/bin/bash
set -e
cd /opt/ai_stack

BACKUP_NAME="ai_stack_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
echo "📦 Создание бэкапа: $BACKUP_NAME"

tar -czvf "/tmp/$BACKUP_NAME" -C /opt ai_stack/

echo "✅ Бэкап создан: /tmp/$BACKUP_NAME"
EOF

# ============================================
# Делаем скрипты исполняемыми
# ============================================
chmod +x "$INSTALL_DIR/scripts/"*.sh

# ============================================
# Генерация ключа и запуск
# ============================================
echo "🔑 Генерация ключа шифрования..."
cd "$INSTALL_DIR"
./scripts/init.sh

echo "🚀 Запуск всех сервисов (это займёт несколько минут)..."
docker compose up -d

echo ""
echo "✅ Установка завершена!"
echo ""
echo "🌐 Доступ к сервисам:"
echo "   Paperclip:           http://$(hostname -I | awk '{print $1}')/"
echo "   FreeLLMAPI:          http://$(hostname -I | awk '{print $1}')/api/"
echo "   FreeLLMAPI Dashboard: http://$(hostname -I | awk '{print $1}'):3001"
echo "   Dockge (управление): http://$(hostname -I | awk '{print $1}'):5001"
echo ""
echo "📂 Все данные находятся в: $INSTALL_DIR"
echo "💡 Для управления используйте: sudo /opt/ai_stack/scripts/<start|stop|status|backup>.sh"
