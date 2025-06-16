#!/bin/bash

# Setup custom cron schedule for Passbolt backups

# Default schedule: every 12 hours
BACKUP_SCHEDULE="${BACKUP_SCHEDULE:-0 */12 * * *}"

# Create crontab with custom schedule
cat > /etc/cron.d/backup-cron << EOF
# Passbolt Backup Cron Job
${BACKUP_SCHEDULE} root /usr/local/bin/backup.sh >> /var/log/cron.log 2>&1

# Empty line required at end of crontab file

EOF

chmod 0644 /etc/cron.d/backup-cron

# For /etc/cron.d/ files, we don't use crontab command
# Instead, we need to ensure cron service picks up the file
service cron reload 2>/dev/null || true

echo "Backup schedule set to: ${BACKUP_SCHEDULE}"
