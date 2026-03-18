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

```bash
# Установка Fail2Ban
sudo apt update && sudo apt install fail2ban -y
# Создание локального конфига
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
```

### Настройка SSHD (systemd)

В `/etc/fail2ban/jail.local`:

```ini
[sshd]
port = change_me
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

### Действие для Docker (Iptables)

Создаем `/etc/fail2ban/action.d/docker-action.conf`:

```ini
[Definition]
actionstart = iptables -N f2b-traefik
              iptables -A f2b-traefik -j RETURN
              iptables -I DOCKER-USER -p tcp -m multiport --dports 80,443 -j f2b-traefik

actionstop = iptables -D DOCKER-USER -p tcp -m multiport --dports 80,443 -j f2b-traefik
             iptables -F f2b-traefik
             iptables -X f2b-traefik

actioncheck = iptables -n -L DOCKER-USER | grep -q 'f2b-traefik[ \t]'

actionban = iptables -I f2b-traefik 1 -s <ip> -j DROP

actionunban = iptables -D f2b-traefik -s <ip> -j DROP
```

### Активация в `/etc/fail2ban/jail.local`

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

### Проверка и перезапуск Fail2Ban

После внесения всех изменений в конфигурационные файлы:

```bash
# Проверка синтаксиса конфигурации (выводит дамп конфига, если ок)
sudo fail2ban-client -d

# Перезапуск сервиса
sudo systemctl restart fail2ban

# Проверка статуса конкретных тюрем (Jails)
sudo fail2ban-client status sshd
sudo fail2ban-client status traefik-json
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

### Применение настроек и перезапуск Docker

После правки `daemon.json` необходимо перезагрузить конфигурацию и сам сервис:

```bash
# Перезагрузка конфигурации демона
sudo systemctl daemon-reload

# Перезапуск сервиса Docker
sudo systemctl restart docker

# Проверка статуса (убедитесь, что Active: active (running))
sudo systemctl status docker

# ВАЖНО: Если Traefik выдает "permission denied" на docker.sock
# Это происходит из-за усиления защиты. Исправьте права:
sudo chmod 666 /var/run/docker.sock
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

## 9. Решение частых проблем (Troubleshooting)

### Ошибка Postgres: "PostgreSQL data in /var/lib/postgresql/data (unused mount/volume)"
Это происходит при обновлении версии образа (например, с 16 на 17) или смене пути монтирования.
**Решение:**
1. Используйте путь монтирования `/var/lib/postgresql` (без `/data` в конце) в `docker-compose.yml`.
2. Если данные не важны (демо-стенд), удалите старый том:
   `docker compose down && docker volume rm demo-stand_postgres_demo_data`

### Ошибка Traefik: "permission denied while trying to connect to the Docker daemon socket"
Проблема с правами доступа к сокету Docker после настройки `daemon.json` (userns-remap).
**Решение:**
Выполните `sudo chmod 666 /var/run/docker.sock` на хосте и перезапустите контейнер Traefik.

### Ошибка Traefik: "open /letsencrypt/acme.json: permission denied"
В режиме `userns-remap` корень контейнера не совпадает с корнем хоста.
**Решение:**
Нужно сменить владельца файлов на ID переназначенного пользователя (обычно `165536`):
```bash
# Узнать ID
grep dockremap /etc/subuid
# Сменить владельца
sudo chown 165536:165536 acme.json
sudo chown -R 165536:165536 ./logs/traefik
```
