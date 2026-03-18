#!/bin/bash
set -e

# Этот лог должен появиться в docker logs demo-postgres
echo ">>> Running init-databases.sh..."

if [ -n "$POSTGRES_MULTIPLE_DATABASES" ]; then
    echo ">>> Found POSTGRES_MULTIPLE_DATABASES: $POSTGRES_MULTIPLE_DATABASES"
    for db_info in $(echo $POSTGRES_MULTIPLE_DATABASES | tr ',' ' '); do
        IFS=':' read -r db user pass <<< "$db_info"
        
        echo ">>> Configuring: Database '$db' for user '$user'"
        
        psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "postgres" <<-EOSQL
            DO \$$
            BEGIN
                IF NOT EXISTS (SELECT FROM pg_catalog.pg_user WHERE usename = '$user') THEN
                    CREATE USER "$user" WITH PASSWORD '$pass';
                END IF;
            END
            \$$;
            
            SELECT 'CREATE DATABASE "$db"'
            WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$db')\gexec
            
            GRANT ALL PRIVILEGES ON DATABASE "$db" TO "$user";
EOSQL

        psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$db" <<-EOSQL
            GRANT ALL ON SCHEMA public TO "$user";
            ALTER SCHEMA public OWNER TO "$user";
EOSQL
    done
    echo ">>> All databases and users configured successfully."
else
    echo ">>> No extra databases requested (POSTGRES_MULTIPLE_DATABASES is empty)."
fi
