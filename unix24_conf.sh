#!/bin/bash

# Проверка dialog
if ! command -v dialog &> /dev/null; then
    echo "Установите dialog: sudo apt install dialog"
    exit 1
fi

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
    echo "Запустите скрипт с правами root: sudo $0"
    exit 1
fi

# ==================== ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ====================

# Получить текущее значение параметра SSH через sshd -T
get_ssh_option() {
    local opt="$1"
    sshd -T 2>/dev/null | grep -i "^$opt " | awk '{print $2}'
}

# Установить параметр SSH в /etc/ssh/sshd_config
set_ssh_option() {
    local opt="$1"
    local val="$2"
    local conf="/etc/ssh/sshd_config"
    
    if grep -qE "^[#[:space:]]*$opt" "$conf"; then
        sed -i "s|^[#[:space:]]*$opt.*|$opt $val|" "$conf"
    else
        echo "$opt $val" >> "$conf"
    fi
    
    # Проверка синтаксиса
    if ! sshd -t 2>/dev/null; then
        dialog --msgbox "Ошибка в конфигурации SSH! Изменения откатаны." 8 50
        return 1
    fi
    systemctl restart ssh
    return 0
}

# ==================== РАЗДЕЛ 1: СОЗДАТЬ ПОЛЬЗОВАТЕЛЯ ====================

create_user() {
    dialog --msgbox "Сейчас откроется интерактивный режим adduser.\nВведите имя, пароль (2 раза) и остальные данные." 10 60
    clear
    echo "=== Создание пользователя ==="
    read -p "Имя нового пользователя: " newuser
    if [ -z "$newuser" ]; then
        dialog --msgbox "Имя не указано. Отмена." 7 40
        return
    fi
    if id "$newuser" &>/dev/null; then
        dialog --msgbox "Пользователь '$newuser' уже существует." 7 45
        return
    fi
    adduser "$newuser"
    usermod -aG sudo "$newuser"
    dialog --msgbox "Пользователь '$newuser' создан и добавлен в группу sudo." 8 50
}

# ==================== РАЗДЕЛ 2: SUDO БЕЗ ПАРОЛЯ ====================

nopasswd_status() {
    local f="/etc/sudoers.d/nopasswd_$SUDO_USER"
    [ -f "$f" ] && echo "on" || echo "off"
}

nopasswd_toggle() {
    local f="/etc/sudoers.d/nopasswd_$SUDO_USER"
    local user="${SUDO_USER:-$USER}"
    
    if [ -f "$f" ]; then
        rm -f "$f"
        dialog --msgbox "Sudo без пароля для '$user' ВЫКЛЮЧЕНО." 7 50
    else
        echo "$user ALL=(ALL) NOPASSWD:ALL" > "$f"
        chmod 440 "$f"
        dialog --msgbox "Sudo без пароля для '$user' ВКЛЮЧЕНО." 7 50
    fi
}

nopasswd_menu() {
    while true; do
        local st=$(nopasswd_status)
        local mark
        [ "$st" = "on" ] && mark="[*] Sudo без пароля (включено)" || mark="[ ] Sudo без пароля (выключено)"
        
        local choice=$(dialog --clear --backtitle "Управление пользователями" \
            --title "Раздел 2: Sudo без пароля" \
            --menu "Пользователь: ${SUDO_USER:-$USER}" 12 60 3 \
            "1" "$mark (Enter - переключить)" \
            "0" "Назад" \
            3>&1 1>&2 2>&3)
        
        case $choice in
            1) nopasswd_toggle ;;
            *) break ;;
        esac
    done
}

# ==================== РАЗДЕЛ 3: НАСТРОЙКИ SSH ====================

ssh_menu() {
    while true; do
        # Читаем состояния
        local svc_status
        systemctl is-active --quiet ssh && svc_status="[*] SSH сервер (работает)" || svc_status="[ ] SSH сервер (остановлен)"
        
        local root_val=$(get_ssh_option "permitrootlogin")
        local root_mark
        [ "$root_val" = "no" ] && root_mark="[*] Запрет root по SSH" || root_mark="[ ] Запрет root по SSH"
        
        local pass_val=$(get_ssh_option "passwordauthentication")
        local pass_mark
        [ "$pass_val" = "no" ] && pass_mark="[*] Запрет входа по паролю (только ключи)" || pass_mark="[ ] Запрет входа по паролю"
        
        local choice=$(dialog --clear --backtitle "Настройки SSH" \
            --title "Раздел 3: SSH" \
            --menu "Выберите пункт (Enter - переключить):" 15 70 4 \
            "1" "$svc_status" \
            "2" "$root_mark" \
            "3" "$pass_mark" \
            "0" "Назад" \
            3>&1 1>&2 2>&3)
        
        case $choice in
            1)
                if systemctl is-active --quiet ssh; then
                    systemctl disable --now ssh
                else
                    systemctl enable --now ssh
                fi
                ;;
            2)
                if [ "$root_val" = "no" ]; then
                    set_ssh_option "PermitRootLogin" "yes"
                else
                    set_ssh_option "PermitRootLogin" "no"
                fi
                ;;
            3)
                if [ "$pass_val" = "no" ]; then
                    set_ssh_option "PasswordAuthentication" "yes"
                else
                    set_ssh_option "PasswordAuthentication" "no"
                fi
                ;;
            *) break ;;
        esac
    done
}

# ==================== РАЗДЕЛ 4: FIREWALL ====================

# Проверяем установлен ли firewall и его состояние
# Возвращает: installed|active, installed|inactive, missing
check_fw() {
    local name="$1"
    case "$name" in
        ufw)
            command -v ufw &>/dev/null || { echo "missing"; return; }
            if ufw status 2>/dev/null | grep -q "Status: active"; then
                echo "active"
            else
                echo "inactive"
            fi
            ;;
        firewalld)
            command -v firewall-cmd &>/dev/null || { echo "missing"; return; }
            if systemctl is-active --quiet firewalld; then
                echo "active"
            else
                echo "inactive"
            fi
            ;;
        nftables)
            command -v nft &>/dev/null || { echo "missing"; return; }
            if systemctl is-active --quiet nftables && [ "$(nft list ruleset 2>/dev/null | wc -l)" -gt 0 ]; then
                echo "active"
            else
                echo "inactive"
            fi
            ;;
        iptables)
            command -v iptables &>/dev/null || { echo "missing"; return; }
            # Активен если есть хоть какие-то правила кроме пустых цепочек
            local rules=$(iptables -L -n 2>/dev/null | grep -vE "^(Chain|target)" | grep -v "^$" | wc -l)
            if [ "$rules" -gt 0 ]; then
                echo "active"
            else
                echo "inactive"
            fi
            ;;
    esac
}

firewall_menu() {
    while true; do
        # Собираем список установленных firewall
        local items=()
        local found=0
        local fw_list=""
        
        for fw in ufw firewalld nftables iptables; do
            local st=$(check_fw "$fw")
            if [ "$st" != "missing" ]; then
                found=1
                local st_text
                [ "$st" = "active" ] && st_text="включен" || st_text="неактивен"
                fw_list="$fw_list  $fw — установлен, $st_text\n"
                items+=("$fw" "$fw ($st_text)")
            fi
        done
        
        if [ $found -eq 0 ]; then
            dialog --msgbox "Firewall не установлен." 7 40
            break
        fi
        
        # Формируем меню: статус + вкл/выкл для каждого
        local menu_items=()
        menu_items+=("show" "Показать статус всех firewall")
        local idx=1
        for fw in ufw firewalld nftables iptables; do
            local st=$(check_fw "$fw")
            if [ "$st" != "missing" ]; then
                if [ "$st" = "active" ]; then
                    menu_items+=("off_$fw" "Выключить $fw")
                else
                    menu_items+=("on_$fw" "Включить $fw")
                fi
            fi
        done
        menu_items+=("0" "Назад")
        
        local choice=$(dialog --clear --backtitle "Firewall" \
            --title "Раздел 4: Firewall" \
            --menu "Выберите действие:" 18 70 10 \
            "${menu_items[@]}" \
            3>&1 1>&2 2>&3)
        
        case $choice in
            show)
                dialog --msgbox "Установленные firewall:\n$fw_list" 12 60
                ;;
            on_ufw)     ufw --force enable ;;
            off_ufw)    ufw disable ;;
            on_firewalld)  systemctl enable --now firewalld ;;
            off_firewalld) systemctl disable --now firewalld ;;
            on_nftables)   systemctl enable --now nftables ;;
            off_nftables)  systemctl disable --now nftables ;;
            on_iptables)
                if command -v netfilter-persistent &>/dev/null; then
                    systemctl enable --now netfilter-persistent
                else
                    dialog --msgbox "iptables установлен, но netfilter-persistent отсутствует.\nВключите через systemctl enable --now netfilter-persistent после установки." 10 60
                fi
                ;;
            off_iptables)
                if command -v netfilter-persistent &>/dev/null; then
                    systemctl disable --now netfilter-persistent
                fi
                ;;
            *) break ;;
        esac
    done
}

# ==================== ГЛАВНОЕ МЕНЮ ====================

while true; do
    choice=$(dialog --clear --backtitle "Панель управления сервером" \
        --title "Главное меню" \
        --menu "Выберите раздел:" 15 60 5 \
        "1" "Создать пользователя (с sudo)" \
        "2" "Sudo без пароля" \
        "3" "Настройки SSH" \
        "4" "Firewall" \
        "0" "Выход" \
        3>&1 1>&2 2>&3)
    
    clear
    case $choice in
        1) create_user ;;
        2) nopasswd_menu ;;
        3) ssh_menu ;;
        4) firewall_menu ;;
        0|*)
            dialog --clear
            echo "Выход."
            exit 0
            ;;
    esac
done