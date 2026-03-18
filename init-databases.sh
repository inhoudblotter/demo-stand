#!/bin/bash
set -e

# Скрипт создает базы данных и пользователей на основе переменной POSTGRES_MULTIPLE_DATABASES
# Формат переменной в .env: DB:USER:PASS,DB:USER:PASS

if [ -n "$POSTGRES_MULTIPLE_DATABASES" ]; then
    echo "Creating multiple databases and users from environment..."
    for db_info in $(echo $POSTGRES_MULTIPLE_DATABASES | tr ',' ' '); do
        # Парсим строку DB:USER:PASS
        IFS=':' read -r db user pass <<< "$db_info"
        
        echo "  - Configuring: Database '$db' for user '$user'"
        
        # Используем внутреннее подключение (без -h localhost)
        # Это предотвращает ошибки "Connection refused" во время инициализации
        psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "postgres" <<-EOSQL
            DO \$$
            BEGIN
                IF NOT EXISTS (SELECT FROM pg_catalog.pg_user WHERE usename = '$user') THEN
                    CREATE USER "$user" WITH PASSWORD '$pass';
                END IF;
            END
            \$$;
            
            -- Создаем базу, если ее нет
            SELECT 'CREATE DATABASE "$db"'
            WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$db')\gexec
            
            GRANT ALL PRIVILEGES ON DATABASE "$db" TO "$user";
EOSQL

        # Настройка прав внутри самой базы
        psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$db" <<-EOSQL
            GRANT ALL ON SCHEMA public TO "$user";
            ALTER SCHEMA public OWNER TO "$user";
EOSQL
    done
    echo "Initialization complete."
fi
