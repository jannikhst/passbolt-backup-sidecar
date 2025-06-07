# Passbolt Backup Sidecar

Docker container that automatically creates backups of Passbolt installations every 12 hours.

## Features

- Automated backups every 12 hours
- MariaDB database dumps
- GPG keys backup
- Container metadata
- Compressed .tar.gz archives
- Optional HTTP endpoint for remote backups
- AES-256-CBC encryption support
- Automatic cleanup of old backups

## Quick Start

1. Copy environment variables:
   ```bash
   cp .env.example .env
   # Edit .env with your values
   ```

2. Copy the example compose file:
   ```bash
   cp example.compose.yml docker-compose.yml
   ```

3. Start the container:
   ```bash
   docker-compose up -d
   ```

## Pre-built Image

The container is automatically built and published to GitHub Container Registry when changes are pushed. You can use the pre-built image by replacing `build: .` with:

```yaml
image: ghcr.io/your-username/passbolt-backup-sidecar:latest
```

## Configuration

### Required Environment Variables

- `MYSQL_PASSWORD` - Database password

### Optional Environment Variables

- `MYSQL_HOST` (default: passbolt-db)
- `MYSQL_USER` (default: passbolt)
- `MYSQL_DATABASE` (default: passbolt)
- `PASSBOLT_CONTAINER` (default: passbolt)
- `BACKUP_RETENTION_DAYS` (default: 30)
- `HTTP_ENDPOINT` - Remote backup URL
- `ENCRYPTION_KEY` - Encryption key for remote backups

## Backup Contents

Each backup includes:
- `database.sql` - Complete MariaDB dump
- `gpg-keys.tar.gz` - GPG keys from /etc/passbolt/gpg
- `passbolt.php` - Passbolt configuration
- `metadata.txt` - Container information

## Remote Backups

Configure HTTP endpoint in `.env`:
```bash
HTTP_ENDPOINT=https://your-backup-server.com/api/backups
ENCRYPTION_KEY=YourSecureKey123
```

Backups are encrypted with AES-256-CBC when `ENCRYPTION_KEY` is set.

## Manual Backup

```bash
docker exec passbolt-backup /usr/local/bin/backup.sh
```

## View Logs

```bash
docker exec passbolt-backup tail -f /var/log/backup.log
```

## Restore Backup

1. Extract: `tar -xzf passbolt-backup-YYYY-MM-DD_HH-MM.tar.gz`
2. Restore DB: `mysql -h passbolt-db -u passbolt -p passbolt < database.sql`
3. Restore GPG: Copy gpg-keys.tar.gz to container and extract

## License

MIT
