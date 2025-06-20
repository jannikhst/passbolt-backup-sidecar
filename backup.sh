#!/bin/bash

# Passbolt Backup Script
# This script creates comprehensive backups of Passbolt installation

set -e

# Add debugging output
echo "[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') - Backup script started"

# Source environment variables (needed for cron)
if [ -f /etc/environment ]; then
    echo "[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') - Sourcing /etc/environment"
    set -a
    source /etc/environment
    set +a
    echo "[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') - Environment variables loaded successfully"
else
    echo "[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') - /etc/environment not found, using container environment"
fi

# Configuration from environment variables
MYSQL_HOST="${MYSQL_HOST:-passbolt-db}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_USER="${MYSQL_USER:-passbolt}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-}"
MYSQL_DATABASE="${MYSQL_DATABASE:-passbolt}"
PASSBOLT_CONTAINER="${PASSBOLT_CONTAINER:-passbolt}"
BACKUP_DIR="${BACKUP_DIR:-/backups}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"

# Backup methods configuration
HTTP_ENDPOINT="${HTTP_ENDPOINT:-}"
HTTP_AUTH_HEADER="${HTTP_AUTH_HEADER:-}"
HTTP_AUTH_VALUE="${HTTP_AUTH_VALUE:-}"
FTP_HOST="${FTP_HOST:-}"
FTP_USER="${FTP_USER:-}"
FTP_PASSWORD="${FTP_PASSWORD:-}"
FTP_PATH="${FTP_PATH:-/backups}"
SFTP_HOST="${SFTP_HOST:-}"
SFTP_USER="${SFTP_USER:-}"
SFTP_PASSWORD="${SFTP_PASSWORD:-}"
SFTP_KEY_FILE="${SFTP_KEY_FILE:-}"
SFTP_PATH="${SFTP_PATH:-/backups}"
SCP_HOST="${SCP_HOST:-}"
SCP_USER="${SCP_USER:-}"
SCP_KEY_FILE="${SCP_KEY_FILE:-}"
SCP_PATH="${SCP_PATH:-/backups}"

# Encryption and compression
ENCRYPTION_KEY="${ENCRYPTION_KEY:-}"
COMPRESSION_LEVEL="${COMPRESSION_LEVEL:-6}"

# Volume mount paths (alternative to docker exec)
PASSBOLT_GPG_VOLUME="${PASSBOLT_GPG_VOLUME:-}"
PASSBOLT_CONFIG_VOLUME="${PASSBOLT_CONFIG_VOLUME:-}"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/backup.log
}

# Detect access method
USE_DOCKER_EXEC=true
if [ -n "${PASSBOLT_GPG_VOLUME}" ] && [ -d "${PASSBOLT_GPG_VOLUME}" ]; then
    USE_DOCKER_EXEC=false
    log "Using direct volume access for GPG keys: ${PASSBOLT_GPG_VOLUME}"
fi

# Error handling
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Create timestamp for backup with seconds for uniqueness
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
BACKUP_NAME="passbolt-backup-${TIMESTAMP}"
TEMP_DIR="/tmp/${BACKUP_NAME}"
FINAL_BACKUP="${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
ENCRYPTED_BACKUP="${BACKUP_DIR}/${BACKUP_NAME}.tar.gz.enc"

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
if [ "${USE_DOCKER_EXEC}" = "true" ]; then
    # Use docker exec method
    if docker exec "${PASSBOLT_CONTAINER}" test -d /etc/passbolt/gpg 2>/dev/null; then
        docker exec "${PASSBOLT_CONTAINER}" tar -czf - -C /etc/passbolt gpg > "${TEMP_DIR}/gpg-keys.tar.gz" || error_exit "GPG keys backup failed"
        log "GPG keys backup completed (via docker exec)"
    else
        log "WARNING: GPG keys directory not found in container"
        touch "${TEMP_DIR}/gpg-keys-not-found.txt"
    fi
else
    # Use direct volume access method
    if [ -d "${PASSBOLT_GPG_VOLUME}" ]; then
        # Create temporary directory with same structure as docker exec method
        temp_gpg_dir="/tmp/gpg-backup-$$"
        mkdir -p "${temp_gpg_dir}/gpg"
        
        # Copy GPG files to temporary directory with gpg subdirectory structure
        cp -r "${PASSBOLT_GPG_VOLUME}"/* "${temp_gpg_dir}/gpg/" || error_exit "Failed to copy GPG keys to temporary directory"
        
        # Create archive with same structure as docker exec method
        tar -czf "${TEMP_DIR}/gpg-keys.tar.gz" -C "${temp_gpg_dir}" gpg || error_exit "GPG keys backup failed"
        
        # Clean up temporary directory
        rm -rf "${temp_gpg_dir}"
        
        log "GPG keys backup completed (via direct volume access)"
    else
        log "WARNING: GPG keys volume not found: ${PASSBOLT_GPG_VOLUME}"
        touch "${TEMP_DIR}/gpg-keys-not-found.txt"
    fi
fi

# 3. Passbolt Configuration Backup
log "Backing up Passbolt configuration..."
if [ "${USE_DOCKER_EXEC}" = "true" ]; then
    # Use docker exec method
    if docker exec "${PASSBOLT_CONTAINER}" test -f /etc/passbolt/passbolt.php 2>/dev/null; then
        docker exec "${PASSBOLT_CONTAINER}" cat /etc/passbolt/passbolt.php > "${TEMP_DIR}/passbolt.php" || log "WARNING: Could not backup passbolt.php"
        log "Configuration backup completed (via docker exec)"
    fi
else
    # Use direct volume access method
    if [ -n "${PASSBOLT_CONFIG_VOLUME}" ] && [ -f "${PASSBOLT_CONFIG_VOLUME}/passbolt.php" ]; then
        cp "${PASSBOLT_CONFIG_VOLUME}/passbolt.php" "${TEMP_DIR}/passbolt.php" || log "WARNING: Could not backup passbolt.php"
        log "Configuration backup completed (via direct volume access)"
    elif [ -f "${PASSBOLT_GPG_VOLUME}/../passbolt.php" ]; then
        # Fallback: try to find config in parent directory of GPG volume
        cp "${PASSBOLT_GPG_VOLUME}/../passbolt.php" "${TEMP_DIR}/passbolt.php" || log "WARNING: Could not backup passbolt.php"
        log "Configuration backup completed (via direct volume access - fallback)"
    fi
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

# 6. Encrypt local backup if encryption key is provided
if [ -n "${ENCRYPTION_KEY}" ]; then
    log "Encrypting local backup..."
    openssl enc -aes-256-cbc -salt -pbkdf2 -iter 100000 -in "${FINAL_BACKUP}" -out "${ENCRYPTED_BACKUP}" -k "${ENCRYPTION_KEY}" || error_exit "Local backup encryption failed"
    
    # Remove unencrypted backup for security
    rm -f "${FINAL_BACKUP}"
    
    # Update variables to point to encrypted backup
    FINAL_BACKUP="${ENCRYPTED_BACKUP}"
    BACKUP_SIZE=$(du -h "${FINAL_BACKUP}" | cut -f1)
    log "Local backup encrypted successfully: ${FINAL_BACKUP} (${BACKUP_SIZE})"
else
    log "WARNING: No encryption key provided - backup stored unencrypted locally"
fi

# 7. Upload backups to remote locations
upload_backup() {
    local backup_file="$1"
    local backup_name="$2"
    
    # Determine if backup is already encrypted (has .enc extension)
    local is_encrypted=false
    if [[ "${backup_file}" == *.enc ]]; then
        is_encrypted=true
        log "Backup is already encrypted locally"
    fi
    
    # HTTP Upload
    if [ -n "${HTTP_ENDPOINT}" ]; then
        log "Uploading backup to HTTP endpoint..."
        
        if [ "${is_encrypted}" = "true" ]; then
            # Backup is already encrypted, upload directly
            local curl_cmd="curl -s -w \"%{http_code}\" -X POST \
                -H \"Content-Type: application/octet-stream\" \
                -H \"X-Backup-Name: ${backup_name}\" \
                -H \"X-Backup-Size: $(stat -c%s "${backup_file}")\""
            
            # Add optional authentication header
            if [ -n "${HTTP_AUTH_HEADER}" ] && [ -n "${HTTP_AUTH_VALUE}" ]; then
                curl_cmd="${curl_cmd} -H \"${HTTP_AUTH_HEADER}: ${HTTP_AUTH_VALUE}\""
            fi
            
            curl_cmd="${curl_cmd} --data-binary \"@${backup_file}\" \"${HTTP_ENDPOINT}\""
            
            local http_response=$(eval ${curl_cmd} || echo "000")
            
            if [ "${http_response}" = "200" ] || [ "${http_response}" = "201" ]; then
                log "Encrypted backup uploaded successfully to HTTP endpoint"
            else
                log "WARNING: Failed to upload backup to HTTP endpoint (HTTP ${http_response})"
            fi
        elif [ -n "${ENCRYPTION_KEY}" ]; then
            # Encrypt backup before sending
            local encrypted_backup="${backup_file}.enc"
            openssl enc -aes-256-cbc -salt -pbkdf2 -iter 100000 -in "${backup_file}" -out "${encrypted_backup}" -k "${ENCRYPTION_KEY}" || {
                log "WARNING: Encryption failed for HTTP upload"
                return 1
            }
            
            # Send encrypted backup with optional auth header
            local curl_cmd="curl -s -w \"%{http_code}\" -X POST \
                -H \"Content-Type: application/octet-stream\" \
                -H \"X-Backup-Name: ${backup_name}.enc\" \
                -H \"X-Backup-Size: $(stat -c%s "${encrypted_backup}")\""
            
            # Add optional authentication header
            if [ -n "${HTTP_AUTH_HEADER}" ] && [ -n "${HTTP_AUTH_VALUE}" ]; then
                curl_cmd="${curl_cmd} -H \"${HTTP_AUTH_HEADER}: ${HTTP_AUTH_VALUE}\""
            fi
            
            curl_cmd="${curl_cmd} --data-binary \"@${encrypted_backup}\" \"${HTTP_ENDPOINT}\""
            
            local http_response=$(eval ${curl_cmd} || echo "000")
            
            if [ "${http_response}" = "200" ] || [ "${http_response}" = "201" ]; then
                log "Encrypted backup uploaded successfully to HTTP endpoint"
                rm -f "${encrypted_backup}"
            else
                log "WARNING: Failed to upload backup to HTTP endpoint (HTTP ${http_response})"
            fi
        else
            # Send unencrypted backup with optional auth header
            local curl_cmd="curl -s -w \"%{http_code}\" -X POST \
                -H \"Content-Type: application/gzip\" \
                -H \"X-Backup-Name: ${backup_name}\" \
                -H \"X-Backup-Size: $(stat -c%s "${backup_file}")\""
            
            # Add optional authentication header
            if [ -n "${HTTP_AUTH_HEADER}" ] && [ -n "${HTTP_AUTH_VALUE}" ]; then
                curl_cmd="${curl_cmd} -H \"${HTTP_AUTH_HEADER}: ${HTTP_AUTH_VALUE}\""
            fi
            
            curl_cmd="${curl_cmd} --data-binary \"@${backup_file}\" \"${HTTP_ENDPOINT}\""
            
            local http_response=$(eval ${curl_cmd} || echo "000")
            
            if [ "${http_response}" = "200" ] || [ "${http_response}" = "201" ]; then
                log "Backup uploaded successfully to HTTP endpoint"
            else
                log "WARNING: Failed to upload backup to HTTP endpoint (HTTP ${http_response})"
            fi
        fi
    fi
    
    # FTP Upload
    if [ -n "${FTP_HOST}" ] && [ -n "${FTP_USER}" ] && [ -n "${FTP_PASSWORD}" ]; then
        log "Uploading backup to FTP server..."
        
        local upload_file="${backup_file}"
        local upload_name="${backup_name}"
        
        if [ "${is_encrypted}" = "false" ] && [ -n "${ENCRYPTION_KEY}" ]; then
            # Only encrypt if not already encrypted
            upload_file="${backup_file}.enc"
            upload_name="${backup_name}.enc"
            openssl enc -aes-256-cbc -salt -pbkdf2 -iter 100000 -in "${backup_file}" -out "${upload_file}" -k "${ENCRYPTION_KEY}" || {
                log "WARNING: Encryption failed for FTP upload"
                return 1
            }
        fi
        
        curl -T "${upload_file}" "ftp://${FTP_HOST}${FTP_PATH}/${upload_name}" \
            --user "${FTP_USER}:${FTP_PASSWORD}" \
            --ftp-create-dirs || {
            log "WARNING: FTP upload failed"
            [ "${is_encrypted}" = "false" ] && [ -n "${ENCRYPTION_KEY}" ] && rm -f "${upload_file}"
            return 1
        }
        
        log "Backup uploaded successfully to FTP server"
        [ "${is_encrypted}" = "false" ] && [ -n "${ENCRYPTION_KEY}" ] && rm -f "${upload_file}"
    fi
    
    # SFTP Upload
    if [ -n "${SFTP_HOST}" ] && [ -n "${SFTP_USER}" ]; then
        log "Uploading backup to SFTP server..."
        
        local upload_file="${backup_file}"
        local upload_name="${backup_name}"
        
        if [ "${is_encrypted}" = "false" ] && [ -n "${ENCRYPTION_KEY}" ]; then
            # Only encrypt if not already encrypted
            upload_file="${backup_file}.enc"
            upload_name="${backup_name}.enc"
            openssl enc -aes-256-cbc -salt -pbkdf2 -iter 100000 -in "${backup_file}" -out "${upload_file}" -k "${ENCRYPTION_KEY}" || {
                log "WARNING: Encryption failed for SFTP upload"
                return 1
            }
        fi
        
        if [ -n "${SFTP_KEY_FILE}" ]; then
            # Key-based authentication
            sftp -i "${SFTP_KEY_FILE}" -o StrictHostKeyChecking=no "${SFTP_USER}@${SFTP_HOST}" <<EOF
mkdir -p ${SFTP_PATH}
put ${upload_file} ${SFTP_PATH}/${upload_name}
quit
EOF
        elif [ -n "${SFTP_PASSWORD}" ]; then
            # Password-based authentication using sshpass
            sshpass -p "${SFTP_PASSWORD}" sftp -o StrictHostKeyChecking=no "${SFTP_USER}@${SFTP_HOST}" <<EOF
mkdir -p ${SFTP_PATH}
put ${upload_file} ${SFTP_PATH}/${upload_name}
quit
EOF
        else
            log "WARNING: SFTP credentials not properly configured"
            [ "${is_encrypted}" = "false" ] && [ -n "${ENCRYPTION_KEY}" ] && rm -f "${upload_file}"
            return 1
        fi
        
        if [ $? -eq 0 ]; then
            log "Backup uploaded successfully to SFTP server"
        else
            log "WARNING: SFTP upload failed"
        fi
        
        [ "${is_encrypted}" = "false" ] && [ -n "${ENCRYPTION_KEY}" ] && rm -f "${upload_file}"
    fi
    
    # SCP Upload
    if [ -n "${SCP_HOST}" ] && [ -n "${SCP_USER}" ] && [ -n "${SCP_KEY_FILE}" ]; then
        log "Uploading backup to SCP server..."
        
        local upload_file="${backup_file}"
        local upload_name="${backup_name}"
        
        if [ "${is_encrypted}" = "false" ] && [ -n "${ENCRYPTION_KEY}" ]; then
            # Only encrypt if not already encrypted
            upload_file="${backup_file}.enc"
            upload_name="${backup_name}.enc"
            openssl enc -aes-256-cbc -salt -pbkdf2 -iter 100000 -in "${backup_file}" -out "${upload_file}" -k "${ENCRYPTION_KEY}" || {
                log "WARNING: Encryption failed for SCP upload"
                return 1
            }
        fi
        
        # Create remote directory and upload
        ssh -i "${SCP_KEY_FILE}" -o StrictHostKeyChecking=no "${SCP_USER}@${SCP_HOST}" "mkdir -p ${SCP_PATH}" && \
        scp -i "${SCP_KEY_FILE}" -o StrictHostKeyChecking=no "${upload_file}" "${SCP_USER}@${SCP_HOST}:${SCP_PATH}/${upload_name}"
        
        if [ $? -eq 0 ]; then
            log "Backup uploaded successfully to SCP server"
        else
            log "WARNING: SCP upload failed"
        fi
        
        [ "${is_encrypted}" = "false" ] && [ -n "${ENCRYPTION_KEY}" ] && rm -f "${upload_file}"
    fi
}

# Upload the backup
upload_backup "${FINAL_BACKUP}" "${BACKUP_NAME}.tar.gz"

# 8. Cleanup old backups
log "Cleaning up old backups (older than ${BACKUP_RETENTION_DAYS} days)..."
find "${BACKUP_DIR}" -name "passbolt-backup-*.tar.gz" -type f -mtime +${BACKUP_RETENTION_DAYS} -delete || log "WARNING: Could not clean up old unencrypted backups"
find "${BACKUP_DIR}" -name "passbolt-backup-*.tar.gz.enc" -type f -mtime +${BACKUP_RETENTION_DAYS} -delete || log "WARNING: Could not clean up old encrypted backups"

log "Backup process completed successfully"
