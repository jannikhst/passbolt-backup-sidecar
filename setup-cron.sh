#!/bin/bash

# Setup custom cron schedule for Passbolt backups

# Default schedule: every 12 hours
BACKUP_SCHEDULE="${BACKUP_SCHEDULE:-0 */12 * * *}"

# Create crontab with custom schedule and proper PATH
cat > /etc/cron.d/backup-cron << EOF
# Set PATH for cron jobs
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Passbolt Backup Cron Job
${BACKUP_SCHEDULE} root /usr/local/bin/backup.sh >> /var/log/cron.log 2>&1

# Empty line required at end of crontab file

EOF

chmod 0644 /etc/cron.d/backup-cron

# For /etc/cron.d/ files, we don't use crontab command
# Instead, we need to ensure cron service picks up the file
service cron reload 2>/dev/null || true

echo "Backup schedule set to: ${BACKUP_SCHEDULE}"
echo "Cron configuration written to /etc/cron.d/backup-cron"

# Debug: Show the created cron file
echo "Cron file contents:"
cat /etc/cron.d/backup-cron
