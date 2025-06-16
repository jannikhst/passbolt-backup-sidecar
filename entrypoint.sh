#!/bin/bash

# Entrypoint script for Passbolt Backup Sidecar

set -e

# Create log files
touch /var/log/cron.log
touch /var/log/backup.log

# Set proper permissions
chmod 644 /var/log/cron.log
chmod 644 /var/log/backup.log

# Ensure backup directory exists
mkdir -p /backups

# Export environment variables properly escaped for shell sourcing
echo "# Environment variables for cron jobs" > /etc/environment
printenv | grep -E '^(MYSQL_|PASSBOLT_|BACKUP_|HTTP_|FTP_|SFTP_|SCP_|ENCRYPTION_|COMPRESSION_)' | while IFS='=' read -r name value; do
    # Properly escape the value by wrapping in single quotes and escaping any single quotes in the value
    escaped_value=$(printf '%s\n' "$value" | sed "s/'/'\\\\''/g")
    echo "export ${name}='${escaped_value}'" >> /etc/environment
done

# Setup custom cron schedule
/usr/local/bin/setup-cron.sh

echo "Starting Passbolt Backup Sidecar..."
echo "Backup schedule: ${BACKUP_SCHEDULE:-0 */12 * * *}"
echo "Backup directory: /backups"
echo "Log files: /var/log/cron.log, /var/log/backup.log"

# Print environment configuration (without sensitive data)
echo "Configuration:"
echo "  MYSQL_HOST: ${MYSQL_HOST:-passbolt-db}"
echo "  MYSQL_PORT: ${MYSQL_PORT:-3306}"
echo "  MYSQL_USER: ${MYSQL_USER:-passbolt}"
echo "  MYSQL_DATABASE: ${MYSQL_DATABASE:-passbolt}"
echo "  PASSBOLT_CONTAINER: ${PASSBOLT_CONTAINER:-passbolt}"
echo "  BACKUP_RETENTION_DAYS: ${BACKUP_RETENTION_DAYS:-30}"
echo "  HTTP_ENDPOINT: ${HTTP_ENDPOINT:-not configured}"
echo "  ENCRYPTION_KEY: ${ENCRYPTION_KEY:+configured}"

# Forward log files to stdout for docker logs visibility
echo "Forwarding cron and backup logs to docker logs..."
tail -f /var/log/cron.log &
tail -f /var/log/backup.log &

# Start cron in foreground
echo "Starting cron daemon..."
exec "$@"
