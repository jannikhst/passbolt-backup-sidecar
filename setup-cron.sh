#!/bin/bash

# Setup custom cron schedule for Passbolt backups

# Default schedule: every 12 hours
BACKUP_SCHEDULE="${BACKUP_SCHEDULE:-0 */12 * * *}"

# Create crontab with custom schedule
cat > /etc/cron.d/backup-cron << EOF
# Passbolt Backup Cron Job
${BACKUP_SCHEDULE} /usr/local/bin/backup.sh >> /var/log/cron.log 2>&1

# Empty line required at end of crontab file

EOF

chmod 0644 /etc/cron.d/backup-cron
crontab /etc/cron.d/backup-cron

echo "Backup schedule set to: ${BACKUP_SCHEDULE}"
