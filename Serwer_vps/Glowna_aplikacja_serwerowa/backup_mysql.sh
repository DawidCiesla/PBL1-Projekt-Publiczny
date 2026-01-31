#!/bin/bash
#
# MySQL Daily Backup Script with 31-day rotation
# Usage: ./backup_mysql.sh
#

set -euo pipefail

# Configuration
BACKUP_DIR="./mysql/backups"
MYSQL_CONTAINER="mysql"
# Nie przechowuj hasła w tym pliku. Odczytujemy z zmiennej środowiskowej.
# Ustaw `MYSQL_ROOT_PASSWORD` w środowisku (np. poprzez plik .env ładowany przed uruchomieniem).

# Pobierz z environment (jeśli nie ustawione, skrypt się przerwie)
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-}"
DATABASE="iot_db"
RETENTION_DAYS=31
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/iot_db_backup_${DATE}.sql.gz"
LOG_FILE="${BACKUP_DIR}/backup.log"

# Create backup directory if it doesn't exist
mkdir -p "${BACKUP_DIR}"

# Log function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

log "Starting MySQL backup..."

if [ -z "${MYSQL_ROOT_PASSWORD}" ]; then
    echo "ERROR: MYSQL_ROOT_PASSWORD nie jest ustawione. Ustaw zmienną środowiskową i uruchom ponownie."
    exit 1
fi

# Perform backup
if docker exec "${MYSQL_CONTAINER}" mysqldump \
    -uroot \
    -p"${MYSQL_ROOT_PASSWORD}" \
    --single-transaction \
    --routines \
    --triggers \
    --events \
    --databases "${DATABASE}" \
    2>/dev/null | gzip > "${BACKUP_FILE}"; then
    
    BACKUP_SIZE=$(du -h "${BACKUP_FILE}" | cut -f1)
    log "Backup successful: ${BACKUP_FILE} (${BACKUP_SIZE})"
else
    log "Backup failed!"
    exit 1
fi

# Remove backups older than RETENTION_DAYS
log "Removing backups older than ${RETENTION_DAYS} days..."
DELETED_COUNT=$(find "${BACKUP_DIR}" -name "iot_db_backup_*.sql.gz" -type f -mtime +${RETENTION_DAYS} -delete -print | wc -l)

if [ "${DELETED_COUNT}" -gt 0 ]; then
    log "Removed ${DELETED_COUNT} old backup(s)"
else
    log "No old backups to remove"
fi

# Show current backups
CURRENT_COUNT=$(find "${BACKUP_DIR}" -name "iot_db_backup_*.sql.gz" -type f | wc -l)
log "Total backups: ${CURRENT_COUNT}"

log "Backup process completed successfully"
