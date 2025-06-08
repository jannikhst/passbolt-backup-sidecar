#!/bin/bash

# Passbolt Restore Script
# This script restores Passbolt backups

set -e

# Configuration from environment variables
MYSQL_HOST="${MYSQL_HOST:-passbolt-db}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_USER="${MYSQL_USER:-passbolt}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-}"
MYSQL_DATABASE="${MYSQL_DATABASE:-passbolt}"
PASSBOLT_CONTAINER="${PASSBOLT_CONTAINER:-passbolt}"
BACKUP_DIR="${BACKUP_DIR:-/backups}"
ENCRYPTION_KEY="${ENCRYPTION_KEY:-}"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Error handling
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Usage function
usage() {
    echo "Usage: $0 [OPTIONS] BACKUP_FILE"
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  -d, --database-only     Restore only database"
    echo "  -g, --gpg-only          Restore only GPG keys"
    echo "  -c, --config-only       Restore only configuration"
    echo "  -f, --force             Force restore without confirmation"
    echo "  -e, --encrypted         Backup file is encrypted"
    echo "  --dry-run               Show what would be restored without doing it"
    echo ""
    echo "Examples:"
    echo "  $0 passbolt-backup-2025-01-07_15-30.tar.gz"
    echo "  $0 -d passbolt-backup-2025-01-07_15-30.tar.gz"
    echo "  $0 -e encrypted-backup.tar.gz.enc"
    echo "  $0 --dry-run passbolt-backup-2025-01-07_15-30.tar.gz"
}

# Parse command line arguments
RESTORE_DATABASE=true
RESTORE_GPG=true
RESTORE_CONFIG=true
FORCE_RESTORE=false
ENCRYPTED_BACKUP=false
DRY_RUN=false
BACKUP_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -d|--database-only)
            RESTORE_DATABASE=true
            RESTORE_GPG=false
            RESTORE_CONFIG=false
            shift
            ;;
        -g|--gpg-only)
            RESTORE_DATABASE=false
            RESTORE_GPG=true
            RESTORE_CONFIG=false
            shift
            ;;
        -c|--config-only)
            RESTORE_DATABASE=false
            RESTORE_GPG=false
            RESTORE_CONFIG=true
            shift
            ;;
        -f|--force)
            FORCE_RESTORE=true
            shift
            ;;
        -e|--encrypted)
            ENCRYPTED_BACKUP=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -*)
            echo "Unknown option $1"
            usage
            exit 1
            ;;
        *)
            BACKUP_FILE="$1"
            shift
            ;;
    esac
done

# Check if backup file is provided
if [ -z "$BACKUP_FILE" ]; then
    echo "Error: Backup file not specified"
    usage
    exit 1
fi

# Check if backup file exists
if [ ! -f "$BACKUP_FILE" ]; then
    error_exit "Backup file not found: $BACKUP_FILE"
fi

log "Starting Passbolt restore from: $BACKUP_FILE"

# Create temporary directory
TEMP_DIR="/tmp/passbolt-restore-$(date +%s)"
mkdir -p "$TEMP_DIR" || error_exit "Failed to create temporary directory"

# Cleanup function
cleanup() {
    log "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Auto-detect encrypted backup and decrypt if needed
RESTORE_FILE="$BACKUP_FILE"
if [[ "$BACKUP_FILE" == *.enc ]] || [ "$ENCRYPTED_BACKUP" = true ]; then
    if [ -z "$ENCRYPTION_KEY" ]; then
        error_exit "ENCRYPTION_KEY environment variable is required for encrypted backups"
    fi
    
    log "Detected encrypted backup file, decrypting..."
    RESTORE_FILE="$TEMP_DIR/decrypted-backup.tar.gz"
    openssl enc -aes-256-cbc -d -pbkdf2 -iter 100000 -in "$BACKUP_FILE" -out "$RESTORE_FILE" -k "$ENCRYPTION_KEY" || error_exit "Failed to decrypt backup"
    log "Backup decrypted successfully"
fi

# Extract backup
log "Extracting backup archive..."
cd "$TEMP_DIR"
tar -xzf "$RESTORE_FILE" || error_exit "Failed to extract backup"

# Find backup directory
BACKUP_EXTRACT_DIR=$(find "$TEMP_DIR" -maxdepth 1 -type d -name "passbolt-backup-*" | head -1)
if [ -z "$BACKUP_EXTRACT_DIR" ]; then
    error_exit "Could not find backup directory in archive"
fi

log "Backup extracted to: $BACKUP_EXTRACT_DIR"

# Show backup contents
log "Backup contents:"
ls -la "$BACKUP_EXTRACT_DIR"

# Show what will be restored
log "Restore plan:"
[ "$RESTORE_DATABASE" = true ] && log "  - Database will be restored"
[ "$RESTORE_GPG" = true ] && log "  - GPG keys will be restored"
[ "$RESTORE_CONFIG" = true ] && log "  - Configuration will be restored"

if [ "$DRY_RUN" = true ]; then
    log "DRY RUN: No actual restore will be performed"
    
    # Show backup metadata
    if [ -f "$BACKUP_EXTRACT_DIR/metadata.txt" ]; then
        log "Backup metadata:"
        cat "$BACKUP_EXTRACT_DIR/metadata.txt"
    fi
    
    exit 0
fi

# Confirmation prompt
if [ "$FORCE_RESTORE" = false ]; then
    echo ""
    echo "WARNING: This will overwrite existing Passbolt data!"
    echo "Make sure you have a current backup before proceeding."
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Restore cancelled by user"
        exit 0
    fi
fi

# Restore database
if [ "$RESTORE_DATABASE" = true ]; then
    if [ -f "$BACKUP_EXTRACT_DIR/database.sql" ]; then
        log "Restoring database..."
        
        if [ -z "$MYSQL_PASSWORD" ]; then
            error_exit "MYSQL_PASSWORD environment variable is required"
        fi
        
        # Stop Passbolt container temporarily
        log "Stopping Passbolt container..."
        docker stop "$PASSBOLT_CONTAINER" 2>/dev/null || log "WARNING: Could not stop Passbolt container"
        
        # Restore database
        mysql \
            --host="$MYSQL_HOST" \
            --port="$MYSQL_PORT" \
            --user="$MYSQL_USER" \
            --password="$MYSQL_PASSWORD" \
            < "$BACKUP_EXTRACT_DIR/database.sql" || error_exit "Database restore failed"
        
        log "Database restored successfully"
        
        # Start Passbolt container
        log "Starting Passbolt container..."
        docker start "$PASSBOLT_CONTAINER" 2>/dev/null || log "WARNING: Could not start Passbolt container"
    else
        log "WARNING: No database backup found in archive"
    fi
fi

# Restore GPG keys
if [ "$RESTORE_GPG" = true ]; then
    if [ -f "$BACKUP_EXTRACT_DIR/gpg-keys.tar.gz" ]; then
        log "Restoring GPG keys..."
        
        # Copy GPG keys to container
        docker cp "$BACKUP_EXTRACT_DIR/gpg-keys.tar.gz" "$PASSBOLT_CONTAINER:/tmp/" || error_exit "Failed to copy GPG keys to container"
        
        # Extract GPG keys in container
        docker exec "$PASSBOLT_CONTAINER" bash -c "
            cd /tmp && 
            tar -xzf gpg-keys.tar.gz && 
            rm -rf /etc/passbolt/gpg/* && 
            cp -r gpg/* /etc/passbolt/gpg/ && 
            chown -R www-data:www-data /etc/passbolt/gpg && 
            rm -rf gpg gpg-keys.tar.gz
        " || error_exit "Failed to restore GPG keys"
        
        log "GPG keys restored successfully"
    else
        log "WARNING: No GPG keys backup found in archive"
    fi
fi

# Restore configuration
if [ "$RESTORE_CONFIG" = true ]; then
    if [ -f "$BACKUP_EXTRACT_DIR/passbolt.php" ]; then
        log "Restoring Passbolt configuration..."
        
        # Backup current config
        docker exec "$PASSBOLT_CONTAINER" cp /etc/passbolt/passbolt.php /etc/passbolt/passbolt.php.backup.$(date +%s) 2>/dev/null || true
        
        # Copy new config to container
        docker cp "$BACKUP_EXTRACT_DIR/passbolt.php" "$PASSBOLT_CONTAINER:/etc/passbolt/passbolt.php" || error_exit "Failed to restore configuration"
        
        # Set proper permissions
        docker exec "$PASSBOLT_CONTAINER" chown www-data:www-data /etc/passbolt/passbolt.php || log "WARNING: Could not set config permissions"
        
        log "Configuration restored successfully"
    else
        log "WARNING: No configuration backup found in archive"
    fi
fi

# Restart Passbolt container to apply changes
log "Restarting Passbolt container..."
docker restart "$PASSBOLT_CONTAINER" || log "WARNING: Could not restart Passbolt container"

log "Restore completed successfully!"
log "Please verify that Passbolt is working correctly."

# Show backup metadata
if [ -f "$BACKUP_EXTRACT_DIR/metadata.txt" ]; then
    log "Restored backup metadata:"
    head -10 "$BACKUP_EXTRACT_DIR/metadata.txt"
fi
