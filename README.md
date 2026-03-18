# Demo Stand Setup

Репозиторий для быстрой настройки демо-стенда с несколькими сервисами на одной машине, работающими на одном домене (через поддомены) с автоматическим SSL от Let's Encrypt.

## Архитектура
- **Traefik (latest)**: Обратный прокси, балансировщик и автоматическое управление SSL. Используется актуальная версия для тестирования последних возможностей.
- **PostgreSQL (latest)**: База данных для всех сервисов.
- **Docker & Docker Compose**: Контейнеризация и управление сервисами.
- **Fail2Ban & UFW**: Защита сервера от брутфорса и DDoS.

## Быстрый старт

### 1. Подготовка сервера
Перед развертыванием сервисов необходимо выполнить базовую настройку безопасности сервера.
Следуйте инструкциям в [SERVER_CONFIG.md](./SERVER_CONFIG.md).

### 2. Настройка окружения
Скопируйте пример файла окружения и заполните его своими данными:
```bash
cp .env.sample .env
nano .env
```
Обязательно укажите:
- `PROJECT_DOMAIN` — ваш основной домен (например, `example.com`).
- `LETSENCRYPT_EMAIL` — ваш email для регистрации SSL сертификатов.
- `POSTGRES_USER` и `POSTGRES_PASSWORD`.

### 3. Инициализация инфраструктуры
Создайте необходимые сети и запустите базовые сервисы (Traefik и Postgres):

```bash
# Создание сетей
docker network create demo-traefik_public
docker network create demo-postgres_demo

# Создание файлов для логов и сертификатов
mkdir -p ./logs/traefik
touch ./logs/traefik/access.log
touch acme.json && chmod 600 acme.json

# Запуск
docker compose up -d
```

### 4. Добавление сервисов
Для добавления новых проектов используйте шаблоны меток (labels) в `docker-compose.yml`. Проекты могут располагаться в отдельных папках или в этом же файле.

Пример меток для Traefik:
```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.my-service.rule=Host(`my-service.example.com`)"
  - "traefik.http.routers.my-service.entrypoints=websecure"
  - "traefik.http.routers.my-service.tls.certresolver=letsencrypt"
```

## Мониторинг и защита
- **Логи**: Доступны в `./logs/traefik/access.log`.
- **Fail2Ban**: Автоматически блокирует IP при попытках подбора паролей или частом обращении к несуществующим ресурсам (см. конфигурацию в `fail2ban/`).
- **Telegram**: Сервер отправляет уведомления о SSH-входах и перезагрузках (настраивается в `SERVER_CONFIG.md`).

## Структура проекта
- `docker-compose.yml` — описание основной инфраструктуры.
- `SERVER_CONFIG.md` — подробный гайд по hardening сервера.
- `fail2ban/` — конфигурационные файлы для защиты.
- `init-databases.sh` — скрипт автоматического создания БД для проектов.
