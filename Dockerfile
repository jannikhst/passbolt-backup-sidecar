FROM debian:bullseye-slim

# Install required packages
RUN apt-get update && apt-get install -y \
    bash \
    cron \
    tar \
    gzip \
    mariadb-client \
    coreutils \
    curl \
    gnupg \
    openssl \
    openssh-client \
    sshpass \
    && rm -rf /var/lib/apt/lists/*

# Create backup directory
RUN mkdir -p /backups

# Copy scripts
COPY backup.sh /usr/local/bin/backup.sh
COPY restore.sh /usr/local/bin/restore.sh
COPY setup-cron.sh /usr/local/bin/setup-cron.sh
RUN chmod +x /usr/local/bin/backup.sh /usr/local/bin/restore.sh /usr/local/bin/setup-cron.sh

# Copy crontab file
COPY crontab /etc/cron.d/backup-cron
RUN chmod 0644 /etc/cron.d/backup-cron

# Apply cron job (will be overridden by setup-cron.sh if BACKUP_SCHEDULE is set)
RUN crontab /etc/cron.d/backup-cron

# Create log file for cron
RUN touch /var/log/cron.log

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Set working directory
WORKDIR /backups

# Expose volume for backups
VOLUME ["/backups"]

# Start cron daemon
ENTRYPOINT ["/entrypoint.sh"]
CMD ["cron", "-f"]
