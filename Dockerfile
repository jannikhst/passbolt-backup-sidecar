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
    && rm -rf /var/lib/apt/lists/*

# Create backup directory
RUN mkdir -p /backups

# Copy backup script
COPY backup.sh /usr/local/bin/backup.sh
RUN chmod +x /usr/local/bin/backup.sh

# Copy crontab file
COPY crontab /etc/cron.d/backup-cron
RUN chmod 0644 /etc/cron.d/backup-cron

# Apply cron job
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
