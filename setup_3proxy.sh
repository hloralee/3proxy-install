#!/bin/bash

# Пути и переменные
CONFIG_FILE="/etc/3proxy/3proxy.cfg"
AUTH_FILE="/etc/3proxy/.proxyauth"
LOG_DIR="/var/log/3proxy"
BIN_PATH="/usr/bin/3proxy"
SERVICE_FILE="/etc/systemd/system/3proxy.service"

# Функция проверки прав
if [[ $EUID -ne 0 ]]; then
   echo "Этот скрипт должен быть запущен от имени root"
   exit 1
fi

# Функция установки
install_3proxy() {
    echo "Обновление системы и установка зависимостей..."
    apt update && apt install -y build-essential wget tar

    echo "Скачивание и сборка 3proxy..."
    cd ~
    wget https://github.com/z3APA3A/3proxy/archive/0.9.4.tar.gz
    tar -xvzf 0.9.4.tar.gz
    cd 3proxy-0.9.4/
    make -f Makefile.Linux
    
    echo "Настройка структуры директорий..."
    mkdir -p /etc/3proxy
    mkdir -p $LOG_DIR
    cp bin/3proxy $BIN_PATH
    
    echo "Создание пользователя"
    useradd -s /usr/sbin/nologin -U -M -r proxyuser
    P_UID=$(id -u proxyuser)
    P_GID=$(id -g proxyuser)

    chown -R proxyuser:proxyuser /etc/3proxy $LOG_DIR $BIN_PATH

    echo "Создание основного конфига"
    cat <<EOF > $CONFIG_FILE
daemon
nserver 8.8.8.8
nserver 8.8.4.4
nscache 65536
timeouts 1 5 30 60 180 1800 15 60

log $LOG_DIR/3proxy.log D
logformat "- +_L%t.%. %N.%p %E %U %C:%c %R:%r %O %I %h %T"
rotate 30

users \$/etc/3proxy/.proxyauth

auth strong
allow *

proxy -p3128 -n -a
socks -p1080

setgid $P_GID
setuid $P_UID
EOF

    echo "Создание файла авторизации"
    touch $AUTH_FILE
    chown proxyuser:proxyuser $AUTH_FILE
    chmod 600 $AUTH_FILE

    echo "Создание Systemd юнита"
    cat <<EOF > $SERVICE_FILE
[Unit]
Description=3proxy Proxy Server
After=network.target

[Service]
Type=simple
ExecStart=$BIN_PATH $CONFIG_FILE
ExecStop=/bin/kill `/usr/bin/pgrep proxyuser`
RemainAfterExit=yes
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable 3proxy
    systemctl start 3proxy

    echo "Установка завершена. Порты: HTTP (3128), SOCKS5 (1080)."
    echo "Нажмите Enter, чтобы вернуть в меню..."
    read
}

# Функция добавления клиента
add_client() {
    echo "--- Добавление клиента ---"
    read -p "Введите имя пользователя: " username
    if grep -q "^$username:" $AUTH_FILE; then
        echo "Ошибка: пользователь $username уже существует!"
    else
        read -p "Введите пароль: " password
        echo "$username:CL:$password" >> $AUTH_FILE
        systemctl restart 3proxy
        echo "Пользователь $username успешно добавлен."
    fi
    echo "Нажмите Enter, чтобы вернуть в меню..."
    read
}

# Функция удаления клиента
revoke_client() {
    echo "--- Удаление клиента ---"
    # Показываем список текущих пользователей для удобства
    echo "Список текущих пользователей:"
    cut -d: -f1 $AUTH_FILE | nl
    
    read -p "Введите имя пользователя для удаления: " username
    if grep -q "^$username:" $AUTH_FILE; then
        sed -i "/^$username:/d" $AUTH_FILE
        systemctl restart 3proxy
        echo "Пользователь $username удален."
    else
        echo "Пользователь не найден."
    fi
    echo "Нажмите Enter, чтобы вернуть в меню..."
    read
}

# Функция полного удаления
remove_3proxy() {
    read -p "Вы уверены, что хотите полностью удалить 3proxy? (y/n): " confirm
    if [[ $confirm == [yY] ]]; then
        systemctl stop 3proxy
        systemctl disable 3proxy
        rm -f $BIN_PATH $SERVICE_FILE
        rm -rf /etc/3proxy $LOG_DIR
        deluser proxyuser
	systemctl daemon-reload
	rm -rf /root/0.9.4.tar.gz /root/3proxy-0.9.4
        echo "3proxy полностью удален. Выход из скрипта."
        exit 0
    fi
}

while true; do
    clear
    echo "================================="
    echo "   3proxy Management Script"
    echo "================================="
    
    if [[ -f "$BIN_PATH" ]]; then
        echo "Status: Installed"
        echo ""
        echo "Select an option:"
        echo "  1) Add a new client"
        echo "  2) Revoke an existing client"
        echo "  3) Remove 3proxy"
        echo "  4) Exit"
        echo ""
        read -p "Option: " opt
        case $opt in
            1) add_client ;;
            2) revoke_client ;;
            3) remove_3proxy ;;
            4) clear; exit 0 ;;
            *) echo "Invalid option. Press Enter..."; read ;;
        esac
    else
        echo "Status: Not Installed"
        echo ""
        echo "Select an option:"
        echo "  1) Install 3proxy"
        echo "  2) Exit"
        echo ""
        read -p "Option: " opt
        case $opt in
            1) install_3proxy ;;
            2) clear; exit 0 ;;
            *) echo "Invalid option. Press Enter..."; read ;;
        esac
    fi
done
