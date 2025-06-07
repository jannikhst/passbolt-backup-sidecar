#!/bin/bash

# Passbolt Backup Script
# This script creates comprehensive backups of Passbolt installation

set -e

# Configuration from environment variables
MYSQL_HOST="${MYSQL_HOST:-passbolt-db}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_USER="${MYSQL_USER:-passbolt}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-}"
MYSQL_DATABASE="${MYSQL_DATABASE:-passbolt}"
PASSBOLT_CONTAINER="${PASSBOLT_CONTAINER:-passbolt}"
BACKUP_DIR="${BACKUP_DIR:-/backups}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
HTTP_ENDPOINT="${HTTP_ENDPOINT:-}"
ENCRYPTION_KEY="${ENCRYPTION_KEY:-}"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/backup.log
}

# Error handling
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Create timestamp for backup
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M')
BACKUP_NAME="passbolt-backup-${TIMESTAMP}"
TEMP_DIR="/tmp/${BACKUP_NAME}"
FINAL_BACKUP="${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"

log "Starting Passbolt backup: ${BACKUP_NAME}"

# Create temporary directory
mkdir -p "${TEMP_DIR}" || error_exit "Failed to create temporary directory"

# 1. Database Backup
log "Creating database backup..."
if [ -z "${MYSQL_PASSWORD}" ]; then
    error_exit "MYSQL_PASSWORD environment variable is required"
fi

mysqldump \
    --host="${MYSQL_HOST}" \
    --port="${MYSQL_PORT}" \
    --user="${MYSQL_USER}" \
    --password="${MYSQL_PASSWORD}" \
    --single-transaction \
    --routines \
    --triggers \
    --add-drop-database \
    --databases "${MYSQL_DATABASE}" \
    > "${TEMP_DIR}/database.sql" || error_exit "Database backup failed"

log "Database backup completed"

# 2. GPG Keys Backup
log "Backing up GPG keys..."
if docker exec "${PASSBOLT_CONTAINER}" test -d /etc/passbolt/gpg 2>/dev/null; then
    docker exec "${PASSBOLT_CONTAINER}" tar -czf - -C /etc/passbolt gpg > "${TEMP_DIR}/gpg-keys.tar.gz" || error_exit "GPG keys backup failed"
    log "GPG keys backup completed"
else
    log "WARNING: GPG keys directory not found in container"
    touch "${TEMP_DIR}/gpg-keys-not-found.txt"
fi

# 3. Passbolt Configuration Backup
log "Backing up Passbolt configuration..."
if docker exec "${PASSBOLT_CONTAINER}" test -f /etc/passbolt/passbolt.php 2>/dev/null; then
    docker exec "${PASSBOLT_CONTAINER}" cat /etc/passbolt/passbolt.php > "${TEMP_DIR}/passbolt.php" || log "WARNING: Could not backup passbolt.php"
fi

# 4. Container Metadata
log "Collecting container metadata..."
{
    echo "# Passbolt Backup Metadata"
    echo "Backup Date: $(date)"
    echo "Backup Script Version: 1.0"
    echo ""
    echo "# Container Information"
    docker inspect "${PASSBOLT_CONTAINER}" 2>/dev/null || echo "Could not inspect container"
} > "${TEMP_DIR}/metadata.txt"

# 5. Create compressed archive
log "Creating compressed archive..."
cd /tmp
tar -czf "${FINAL_BACKUP}" "${BACKUP_NAME}/" || error_exit "Failed to create compressed archive"

# Clean up temporary directory
rm -rf "${TEMP_DIR}"

# Get backup size
BACKUP_SIZE=$(du -h "${FINAL_BACKUP}" | cut -f1)
log "Backup created successfully: ${FINAL_BACKUP} (${BACKUP_SIZE})"

# 6. Optional: Send to HTTP endpoint
if [ -n "${HTTP_ENDPOINT}" ]; then
    log "Sending backup to HTTP endpoint..."
    
    if [ -n "${ENCRYPTION_KEY}" ]; then
        # Encrypt backup before sending
        ENCRYPTED_BACKUP="${FINAL_BACKUP}.enc"
        openssl enc -aes-256-cbc -salt -in "${FINAL_BACKUP}" -out "${ENCRYPTED_BACKUP}" -k "${ENCRYPTION_KEY}" || error_exit "Encryption failed"
        
        # Send encrypted backup
        HTTP_RESPONSE=$(curl -s -w "%{http_code}" -X POST \
            -H "Content-Type: application/octet-stream" \
            -H "X-Backup-Name: ${BACKUP_NAME}.tar.gz.enc" \
            -H "X-Backup-Size: $(stat -c%s "${ENCRYPTED_BACKUP}")" \
            --data-binary "@${ENCRYPTED_BACKUP}" \
            "${HTTP_ENDPOINT}" || echo "000")
        
        if [ "${HTTP_RESPONSE}" = "200" ] || [ "${HTTP_RESPONSE}" = "201" ]; then
            log "Encrypted backup sent successfully to HTTP endpoint"
            rm -f "${ENCRYPTED_BACKUP}"
        else
            log "WARNING: Failed to send backup to HTTP endpoint (HTTP ${HTTP_RESPONSE})"
        fi
    else
        # Send unencrypted backup
        HTTP_RESPONSE=$(curl -s -w "%{http_code}" -X POST \
            -H "Content-Type: application/gzip" \
            -H "X-Backup-Name: ${BACKUP_NAME}.tar.gz" \
            -H "X-Backup-Size: $(stat -c%s "${FINAL_BACKUP}")" \
            --data-binary "@${FINAL_BACKUP}" \
            "${HTTP_ENDPOINT}" || echo "000")
        
        if [ "${HTTP_RESPONSE}" = "200" ] || [ "${HTTP_RESPONSE}" = "201" ]; then
            log "Backup sent successfully to HTTP endpoint"
        else
            log "WARNING: Failed to send backup to HTTP endpoint (HTTP ${HTTP_RESPONSE})"
        fi
    fi
fi

# 7. Cleanup old backups
log "Cleaning up old backups (older than ${BACKUP_RETENTION_DAYS} days)..."
find "${BACKUP_DIR}" -name "passbolt-backup-*.tar.gz" -type f -mtime +${BACKUP_RETENTION_DAYS} -delete || log "WARNING: Could not clean up old backups"

log "Backup process completed successfully"
