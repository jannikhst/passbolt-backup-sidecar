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

# Volume mount paths (if available)
PASSBOLT_GPG_VOLUME="${PASSBOLT_GPG_VOLUME:-}"
PASSBOLT_CONFIG_VOLUME="${PASSBOLT_CONFIG_VOLUME:-}"

# Check available access methods
DOCKER_AVAILABLE=false
VOLUME_ACCESS=false

# Check if Docker socket is available
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    DOCKER_AVAILABLE=true
fi

# Check if volume mounts are available
if [ -n "$PASSBOLT_GPG_VOLUME" ] && [ -d "$PASSBOLT_GPG_VOLUME" ]; then
    VOLUME_ACCESS=true
fi

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to wait for user confirmation
wait_for_user_action() {
    local action="$1"
    echo ""
    echo "MANUAL ACTION REQUIRED:"
    echo "$action"
    echo ""
    echo "NOTE: This manual step can be automated by mounting the Docker socket:"
    echo "  volumes:"
    echo "    - /var/run/docker.sock:/var/run/docker.sock"
    echo ""
    read -p "Press Enter when you have completed this action..." -r
}

# Function to stop container (with Docker socket or manual)
stop_container() {
    local container="$1"
    if [ "$DOCKER_AVAILABLE" = true ]; then
        log "Stopping $container container..."
        docker stop "$container" 2>/dev/null || log "WARNING: Could not stop $container container"
    else
        wait_for_user_action "Please stop the $container container manually:
  docker stop $container"
    fi
}

# Function to start container (with Docker socket or manual)
start_container() {
    local container="$1"
    if [ "$DOCKER_AVAILABLE" = true ]; then
        log "Starting $container container..."
        docker start "$container" 2>/dev/null || log "WARNING: Could not start $container container"
    else
        wait_for_user_action "Please start the $container container manually:
  docker start $container"
    fi
}

# Function to restart container (with Docker socket or manual)
restart_container() {
    local container="$1"
    if [ "$DOCKER_AVAILABLE" = true ]; then
        log "Restarting $container container..."
        docker restart "$container" || log "WARNING: Could not restart $container container"
    else
        wait_for_user_action "Please restart the $container container manually:
  docker restart $container"
    fi
}

# Function to copy files to container (with Docker socket, volume mount, or manual)
copy_to_container() {
    local source="$1"
    local container="$2"
    local destination="$3"
    
    if [ "$DOCKER_AVAILABLE" = true ]; then
        docker cp "$source" "$container:$destination" || error_exit "Failed to copy $source to container"
    else
        wait_for_user_action "Please copy the file to the container manually:
  docker cp $source $container:$destination"
    fi
}

# Function to execute command in container (with Docker socket or manual)
exec_in_container() {
    local container="$1"
    local command="$2"
    
    if [ "$DOCKER_AVAILABLE" = true ]; then
        docker exec "$container" bash -c "$command" || error_exit "Failed to execute command in container"
    else
        wait_for_user_action "Please execute the following command in the $container container manually:
  docker exec $container bash -c \"$command\""
    fi
}

# Function to restore GPG keys (with volume mount or container access)
restore_gpg_keys() {
    local gpg_backup="$1"
    
    if [ "$VOLUME_ACCESS" = true ]; then
        log "Restoring GPG keys via volume mount..."
        
        # Extract GPG keys to temporary directory
        local temp_gpg_dir="$TEMP_DIR/gpg-restore"
        mkdir -p "$temp_gpg_dir"
        cd "$temp_gpg_dir"
        
        log "Extracting GPG keys archive: $gpg_backup"
        tar -xzf "$gpg_backup" || error_exit "Failed to extract GPG keys"
        
        # Debug: Show what was extracted
        log "Contents after extraction:"
        ls -la .
        
        # Check if gpg directory exists
        if [ ! -d "gpg" ]; then
            error_exit "GPG directory not found after extraction. Archive structure may be different."
        fi
        
        # Check if gpg directory has contents
        if [ ! "$(ls -A gpg 2>/dev/null)" ]; then
            error_exit "GPG directory is empty after extraction."
        fi
        
        log "GPG directory contents:"
        ls -la gpg/
        
        # Clear existing GPG keys
        log "Clearing existing GPG keys from volume: $PASSBOLT_GPG_VOLUME"
        rm -rf "$PASSBOLT_GPG_VOLUME"/* || error_exit "Failed to clear existing GPG keys"
        
        # Copy GPG keys directly to volume
        log "Copying GPG keys to volume..."
        cp -r gpg/* "$PASSBOLT_GPG_VOLUME/" || error_exit "Failed to copy GPG keys to volume"
        
        log "GPG keys restored successfully via volume mount"
    else
        log "Restoring GPG keys via container access..."
        
        # Copy GPG keys to container
        copy_to_container "$gpg_backup" "$PASSBOLT_CONTAINER" "/tmp/"
        
        # Extract GPG keys in container
        exec_in_container "$PASSBOLT_CONTAINER" "
            cd /tmp && 
            tar -xzf gpg-keys.tar.gz && 
            rm -rf /etc/passbolt/gpg/* && 
            cp -r gpg/* /etc/passbolt/gpg/ && 
            chown -R www-data:www-data /etc/passbolt/gpg && 
            rm -rf gpg gpg-keys.tar.gz
        "
        
        log "GPG keys restored successfully via container access"
    fi
}

# Function to restore configuration (with volume mount or container access)
restore_config() {
    local config_backup="$1"
    
    if [ "$VOLUME_ACCESS" = true ] && [ -n "$PASSBOLT_CONFIG_VOLUME" ] && [ -d "$PASSBOLT_CONFIG_VOLUME" ]; then
        log "Restoring configuration via volume mount..."
        
        # Backup current config
        if [ -f "$PASSBOLT_CONFIG_VOLUME/passbolt.php" ]; then
            cp "$PASSBOLT_CONFIG_VOLUME/passbolt.php" "$PASSBOLT_CONFIG_VOLUME/passbolt.php.backup.$(date +%s)" || true
        fi
        
        # Copy new config to volume
        cp "$config_backup" "$PASSBOLT_CONFIG_VOLUME/passbolt.php" || error_exit "Failed to restore configuration to volume"
        
        log "Configuration restored successfully via volume mount"
    else
        log "Restoring configuration via container access..."
        
        # Backup current config
        if [ "$DOCKER_AVAILABLE" = true ]; then
            docker exec "$PASSBOLT_CONTAINER" cp /etc/passbolt/passbolt.php /etc/passbolt/passbolt.php.backup.$(date +%s) 2>/dev/null || true
        else
            wait_for_user_action "Please backup the current configuration manually:
  docker exec $PASSBOLT_CONTAINER cp /etc/passbolt/passbolt.php /etc/passbolt/passbolt.php.backup.$(date +%s)"
        fi
        
        # Copy new config to container
        copy_to_container "$config_backup" "$PASSBOLT_CONTAINER" "/etc/passbolt/passbolt.php"
        
        # Set proper permissions
        exec_in_container "$PASSBOLT_CONTAINER" "chown www-data:www-data /etc/passbolt/passbolt.php"
        
        log "Configuration restored successfully via container access"
    fi
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

# Show access method status
if [ "$DOCKER_AVAILABLE" = true ]; then
    log "Docker socket available - container operations will be automated"
elif [ "$VOLUME_ACCESS" = true ]; then
    log "Volume mount access available - direct file operations will be used"
    log "GPG volume: $PASSBOLT_GPG_VOLUME"
    [ -n "$PASSBOLT_CONFIG_VOLUME" ] && log "Config volume: $PASSBOLT_CONFIG_VOLUME"
else
    log "No direct access available - manual container operations will be required"
    log "To enable automation, either:"
    log "  1. Mount Docker socket: -v /var/run/docker.sock:/var/run/docker.sock"
    log "  2. Mount volumes and set PASSBOLT_GPG_VOLUME environment variable"
fi

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
        stop_container "$PASSBOLT_CONTAINER"
        
        # Restore database
        mysql \
            --host="$MYSQL_HOST" \
            --port="$MYSQL_PORT" \
            --user="$MYSQL_USER" \
            --password="$MYSQL_PASSWORD" \
            < "$BACKUP_EXTRACT_DIR/database.sql" || error_exit "Database restore failed"
        
        log "Database restored successfully"
        
        # Start Passbolt container
        start_container "$PASSBOLT_CONTAINER"
    else
        log "WARNING: No database backup found in archive"
    fi
fi

# Restore GPG keys
if [ "$RESTORE_GPG" = true ]; then
    if [ -f "$BACKUP_EXTRACT_DIR/gpg-keys.tar.gz" ]; then
        restore_gpg_keys "$BACKUP_EXTRACT_DIR/gpg-keys.tar.gz"
    else
        log "WARNING: No GPG keys backup found in archive"
    fi
fi

# Restore configuration
if [ "$RESTORE_CONFIG" = true ]; then
    if [ -f "$BACKUP_EXTRACT_DIR/passbolt.php" ]; then
        restore_config "$BACKUP_EXTRACT_DIR/passbolt.php"
    else
        log "WARNING: No configuration backup found in archive"
    fi
fi

# Restart Passbolt container to apply changes
restart_container "$PASSBOLT_CONTAINER"

log "Restore completed successfully!"
log "Please verify that Passbolt is working correctly."

# Show backup metadata
if [ -f "$BACKUP_EXTRACT_DIR/metadata.txt" ]; then
    log "Restored backup metadata:"
    head -10 "$BACKUP_EXTRACT_DIR/metadata.txt"
fi
