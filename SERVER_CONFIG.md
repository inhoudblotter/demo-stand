# Инструкция по инициализации и защите сервера (Hardening)

Данный документ содержит шаги по настройке безопасности (Hardening) сервера на базе Ubuntu/Debian для развертывания демо-стендов.

## 1. Обновление системы и автоматизация патчей

```bash
# Обновление списка пакетов и установленных программ
sudo apt update && sudo apt upgrade -y

# Установка и настройка автоматических обновлений безопасности
sudo apt install unattended-upgrades -y
sudo dpkg-reconfigure -plow unattended-upgrades

# Установка docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
rm get-docker.sh
```

## 2. Управление пользователями

Избегайте использования `root`. Создаем отдельного пользователя `webmaster`.

```bash
# Создание пользователя
adduser webmaster
# Добавление в группу sudo
usermod -aG sudo webmaster

# Настройка SSH-доступа (копируем ключи от текущего)
mkdir -p /home/webmaster/.ssh
cp ~/.ssh/authorized_keys /home/webmaster/.ssh/authorized_keys

# Установка правильных прав доступа
chown -R webmaster:webmaster /home/webmaster/.ssh
chmod 700 /home/webmaster/.ssh
chmod 600 /home/webmaster/.ssh/authorized_keys
```

## 3. Усиление защиты SSH

**Рекомендуемые параметры в `/etc/ssh/sshd_config`:**

```ini
# Смена стандартного порта
Port 2002
# Запрещаем вход root-пользователю
PermitRootLogin no
# Вход ТОЛЬКО по SSH-ключам
PasswordAuthentication no
# Отключаем пустые пароли
PermitEmptyPasswords no
# Отключаем интерактивный вход
KbdInteractiveAuthentication no
# Отключаем X11 forwarding
X11Forwarding no
# Разрешаем только Pubkey
PubkeyAuthentication yes
```

**Важно:** Сначала разрешите порт в Firewall (раздел 4), затем перезагрузите SSH:
```bash
sudo sshd -t && sudo service ssh restart
```

## 4. Настройка Firewall (UFW)

Настраиваем политику «запрещено всё, что не разрешено» с ограничением скорости (Rate Limiting).

```bash
# Сброс настроек и установка политик по умолчанию
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Разрешаем SSH на кастомном порту с ограничением перебора
sudo ufw limit 2002/tcp

# Разрешаем веб-трафик с ограничением (защита от DDoS)
sudo ufw limit 80/tcp
sudo ufw limit 443/tcp

# Включаем фаервол
sudo ufw enable
```

## 5. Sysctl Hardening

Блокировка ICMP, защита от SYN-flood и ARP-спуфинга.

```bash
sudo nano /etc/sysctl.d/99-hardening.conf
```

```conf
# SYN flood защита
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048

# Блокировка ICMP (DDoS)
net.ipv4.icmp_echo_ignore_all = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1

# ARP спуфинг
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
```

Применить: `sudo sysctl -p /etc/sysctl.d/99-hardening.conf`

## 6. Защита от перебора (Fail2Ban)

### Настройка SSHD (systemd)
В `/etc/fail2ban/jail.local`:
```ini
[sshd]
enabled = true
backend = systemd
maxretry = 3
bantime = 7200
```

### Фильтр для Traefik (JSON logs)
Создаем `/etc/fail2ban/filter.d/traefik-json.conf`:
```ini
[Definition]
failregex = "ClientIP\":\"<HOST>\".*?(?:\"status\":4[02][1-9]|\"DownstreamStatusCode\":4[02][1-9]|\"status\":429)
ignoreregex =
```

### Активация в `jail.local`
```ini
[traefik-json]
enabled = true
logpath = /home/webmaster/demo-stand/logs/traefik/access.log
filter = traefik-json
maxretry = 20
bantime = 3600
findtime = 600
chain = DOCKER-USER
```

## 7. Оптимизация Docker

```bash
sudo nano /etc/docker/daemon.json
```

```json
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "live-restore": true,
  "userland-proxy": false,
  "no-new-privileges": true,
  "icc": false,
  "userns-remap": "default"
}
```

Включите AppArmor:
```bash
sudo apt install apparmor-utils -y
sudo aa-status
```

## 8. Мониторинг в Telegram

### Алерт при SSH-входе
Создаем `/etc/profile.d/ssh-alert.sh`:
```bash
#!/bin/bash
TOKEN="BOT_TOKEN"
CHAT_ID="ADMIN_CHAT"

if [ -n "$SSH_CLIENT" ] || [ -n "$SSH_TTY" ]; then
    IP=$(echo $SSH_CONNECTION | awk '{print $1}')
    HOSTNAME=$(hostname)
    NOW=$(date "+%Y-%m-%d %H:%M:%S")
    TEXT="🚨 <b>SSH Login Alert</b>%0AUser: <b>$USER</b>%0AIP: <code>$IP</code>%0AServer: <code>$HOSTNAME</code>%0ADate: <code>$NOW</code>"
    curl -s -X POST "https://api.telegram.org/bot$TOKEN/sendMessage" -d chat_id=$CHAT_ID -d text="$TEXT" -d parse_mode="HTML" > /dev/null 2>&1 &
fi
```

### Уведомление о перезагрузке
В `sudo crontab -e`:
```bash
@reboot curl -s -X POST "https://api.telegram.org/botBOT_TOKEN/sendMessage" -d chat_id=ADMIN_CHAT -d text="⚡ Server <b>$(hostname)</b> Started/Rebooted" -d parse_mode="HTML" > /dev/null 2>&1
```
