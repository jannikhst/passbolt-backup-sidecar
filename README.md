# Passbolt Backup Sidecar

Docker container that automatically creates backups of Passbolt installations on a schedule.

## Features

- **Customizable backup schedule** (default: every 12 hours)
- **MariaDB database dumps** with mysqldump
- **GPG keys backup** from /etc/passbolt/gpg
- **Container metadata** and configuration
- **Compressed .tar.gz archives** with configurable compression
- **Multiple upload methods**: HTTP POST, FTP, SFTP, SCP
- **AES-256-CBC encryption** for all backup methods
- **Automatic cleanup** of old backups
- **Comprehensive restore script** with selective restore options
- **Dry-run mode** for testing

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
image: ghcr.io/jannikhst/passbolt-backup-sidecar:latest
```

## Configuration

### Required Environment Variables

- `MYSQL_PASSWORD` - Database password

### Optional Environment Variables

#### Basic Configuration
- `MYSQL_HOST` (default: passbolt-db)
- `MYSQL_USER` (default: passbolt)
- `MYSQL_DATABASE` (default: passbolt)
- `PASSBOLT_CONTAINER` (default: passbolt)
- `BACKUP_RETENTION_DAYS` (default: 30)
- `BACKUP_SCHEDULE` (default: 0 */12 * * *) - Cron schedule
- `COMPRESSION_LEVEL` (default: 6) - gzip compression level (1-9)

#### Security
- `ENCRYPTION_KEY` - Optional AES-256-CBC encryption key (encrypts backups for ALL upload methods)

#### Upload Methods
- `HTTP_ENDPOINT`, `HTTP_AUTH_HEADER`, `HTTP_AUTH_VALUE` - HTTP POST configuration
- `FTP_HOST`, `FTP_USER`, `FTP_PASSWORD`, `FTP_PATH` - FTP configuration
- `SFTP_HOST`, `SFTP_USER`, `SFTP_PASSWORD`, `SFTP_KEY_FILE`, `SFTP_PATH` - SFTP configuration
- `SCP_HOST`, `SCP_USER`, `SCP_KEY_FILE`, `SCP_PATH` - SCP configuration

## Backup Contents

Each backup includes:
- `database.sql` - Complete MariaDB dump
- `gpg-keys.tar.gz` - GPG keys from /etc/passbolt/gpg
- `passbolt.php` - Passbolt configuration
- `metadata.txt` - Container information

## Backup Schedule Examples

```bash
# Every 12 hours (default)
BACKUP_SCHEDULE="0 */12 * * *"

# Daily at 2 AM
BACKUP_SCHEDULE="0 2 * * *"

# Every 6 hours
BACKUP_SCHEDULE="0 */6 * * *"

# Weekly on Sunday at 3 AM
BACKUP_SCHEDULE="0 3 * * 0"

# Twice daily at 6 AM and 6 PM
BACKUP_SCHEDULE="0 6,18 * * *"
```

## Remote Upload Methods

### HTTP POST
```bash
HTTP_ENDPOINT=https://your-backup-server.com/api/backups
ENCRYPTION_KEY=YourSecureKey123

# Optional authentication header
HTTP_AUTH_HEADER=Authorization
HTTP_AUTH_VALUE=Bearer your_api_token

# Or with API key
HTTP_AUTH_HEADER=X-API-Key
HTTP_AUTH_VALUE=your_api_key
```

### FTP
```bash
FTP_HOST=ftp.example.com
FTP_USER=backup_user
FTP_PASSWORD=backup_password
FTP_PATH=/backups
```

### SFTP (with password)
```bash
SFTP_HOST=sftp.example.com
SFTP_USER=backup_user
SFTP_PASSWORD=backup_password
SFTP_PATH=/backups
```

### SFTP (with key file)
```bash
SFTP_HOST=sftp.example.com
SFTP_USER=backup_user
SFTP_KEY_FILE=/keys/sftp_key
SFTP_PATH=/backups
```

### SCP (requires key file)
```bash
SCP_HOST=scp.example.com
SCP_USER=backup_user
SCP_KEY_FILE=/keys/scp_key
SCP_PATH=/backups
```

## Manual Operations

### Manual Backup
```bash
docker exec passbolt-backup /usr/local/bin/backup.sh
```

### View Logs
```bash
# Backup logs
docker exec passbolt-backup tail -f /var/log/backup.log

# Cron logs
docker exec passbolt-backup tail -f /var/log/cron.log

# Container logs
docker logs passbolt-backup
```

## Restore Operations

### Using the Restore Script
```bash
# Full restore
docker exec passbolt-backup /usr/local/bin/restore.sh /backups/passbolt-backup-2025-01-07_15-30.tar.gz

# Database only
docker exec passbolt-backup /usr/local/bin/restore.sh -d /backups/passbolt-backup-2025-01-07_15-30.tar.gz

# GPG keys only
docker exec passbolt-backup /usr/local/bin/restore.sh -g /backups/passbolt-backup-2025-01-07_15-30.tar.gz

# Configuration only
docker exec passbolt-backup /usr/local/bin/restore.sh -c /backups/passbolt-backup-2025-01-07_15-30.tar.gz

# Encrypted backup
docker exec passbolt-backup /usr/local/bin/restore.sh -e /backups/encrypted-backup.tar.gz.enc

# Dry run (show what would be restored)
docker exec passbolt-backup /usr/local/bin/restore.sh --dry-run /backups/passbolt-backup-2025-01-07_15-30.tar.gz

# Force restore without confirmation
docker exec passbolt-backup /usr/local/bin/restore.sh -f /backups/passbolt-backup-2025-01-07_15-30.tar.gz
```

### Manual Restore Steps
1. Extract: `tar -xzf passbolt-backup-YYYY-MM-DD_HH-MM.tar.gz`
2. Restore DB: `mysql -h passbolt-db -u passbolt -p passbolt < database.sql`
3. Restore GPG: Copy gpg-keys.tar.gz to container and extract

## Encryption

### Automatic Encryption for All Upload Methods

When you set the `ENCRYPTION_KEY` environment variable, **ALL backup uploads are automatically encrypted** using AES-256-CBC:

- ✅ **HTTP POST** - Encrypted before upload
- ✅ **FTP** - Encrypted before upload  
- ✅ **SFTP** - Encrypted before upload
- ✅ **SCP** - Encrypted before upload

### How It Works

```bash
# Set encryption key to enable encryption for ALL methods
ENCRYPTION_KEY=YourSecureEncryptionKey123

# Configure any upload method - encryption happens automatically
HTTP_ENDPOINT=https://backup.example.com/api/backups
FTP_HOST=ftp.example.com
SFTP_HOST=sftp.example.com
SCP_HOST=scp.example.com
```

### File Naming
- **Without encryption**: `passbolt-backup-2025-01-07_15-30.tar.gz`
- **With encryption**: `passbolt-backup-2025-01-07_15-30.tar.gz.enc`

### Manual Encryption/Decryption
```bash
# Encrypt backup manually
openssl enc -aes-256-cbc -salt -in backup.tar.gz -out backup.tar.gz.enc -k "YourEncryptionKey"

# Decrypt backup manually
openssl enc -aes-256-cbc -d -in backup.tar.gz.enc -out backup.tar.gz -k "YourEncryptionKey"
```

### Important Notes
- 🔒 **Optional**: Only encrypts when `ENCRYPTION_KEY` is set
- 🌐 **Universal**: Works with all upload methods automatically
- 🔐 **Secure**: Uses AES-256-CBC with salt
- 🧹 **Clean**: Temporary encrypted files are automatically deleted after upload

## License

MIT
