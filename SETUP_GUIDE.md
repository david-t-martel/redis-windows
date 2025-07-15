# Redis for Windows - Complete Setup Guide

## Overview

This project provides Redis for Windows with three different ways to run it:
1. **Direct execution** using `start.bat`
2. **Command line** execution
3. **Windows Service** for automatic startup

## Prerequisites

- Windows 10/11 or Windows Server 2016+
- .NET 8.0 Runtime (for the service wrapper)
- Administrator privileges (for service installation)

## Project Structure

```
redis-windows/
├── RedisService.exe          # Windows service wrapper (built from source)
├── redis-server.exe          # Redis server binary (from build process)
├── redis-cli.exe             # Redis command line interface
├── redis.conf                # Redis configuration file
├── start.bat                 # Quick start script
├── install_redis_service.bat # Service installation script
├── uninstall_redis_service.bat # Service removal script
└── README.md                 # This file
```

## Getting Redis Binaries

The Redis binaries (`redis-server.exe`, `redis-cli.exe`, etc.) are built using GitHub Actions workflows. There are two ways to get them:

### Option 1: Download from Releases (Recommended)

1. Go to the [Releases page](https://github.com/david-t-martel/redis-windows/releases)
2. Download the latest `Redis-X.X.X-Windows-x64-with-Service.zip`
3. Extract to your desired directory

### Option 2: Build from Source

The project uses GitHub Actions to build Redis from source using MSYS2 and Cygwin:

1. The workflow downloads Redis source code from the official repository
2. Builds it using both MSYS2 and Cygwin environments
3. Creates distribution packages with the service wrapper
4. Generates checksums for verification

## Installation Methods

### Method 1: Quick Start (Development)

1. Extract the downloaded package
2. Double-click `start.bat` to run Redis immediately
3. Redis will start with the default configuration

### Method 2: Command Line

Open PowerShell or Command Prompt in the Redis directory:

```powershell
# PowerShell
./redis-server.exe redis.conf

# Command Prompt
redis-server.exe redis.conf
```

### Method 3: Windows Service (Production)

For production environments, install Redis as a Windows service:

1. **Run as Administrator**: Right-click PowerShell and select "Run as administrator"

2. **Install the service**:
   ```powershell
   sc.exe create Redis binpath="C:\path\to\your\redis\RedisService.exe" start=auto
   ```

3. **Start the service**:
   ```powershell
   net start Redis
   ```

4. **Verify it's running**:
   ```powershell
   sc.exe query Redis
   ```

#### Service Management Commands

```powershell
# Start service
net start Redis

# Stop service
net stop Redis

# Restart service
net stop Redis && net start Redis

# Uninstall service
sc.exe delete Redis
```

## Configuration

### Basic Configuration (`redis.conf`)

Key settings for Windows:

```conf
# Network
bind 127.0.0.1
port 6379

# General
daemonize no
pidfile ./redis.pid
logfile redis.log
loglevel notice

# Persistence
save 900 1
save 300 10
save 60 10000

dbfilename dump.rdb
dir ./

# Memory
maxmemory 256mb
maxmemory-policy allkeys-lru

# Security (uncomment and set password)
# requirepass your_password_here

# Windows-specific
tcp-keepalive 60
```

### Security Best Practices

1. **Set a password**:
   ```conf
   requirepass your_strong_password_here
   ```

2. **Bind to specific interfaces**:
   ```conf
   bind 127.0.0.1 192.168.1.100
   ```

3. **Disable dangerous commands**:
   ```conf
   rename-command FLUSHDB ""
   rename-command FLUSHALL ""
   rename-command CONFIG ""
   ```

### Performance Tuning

1. **Memory settings**:
   ```conf
   maxmemory 2gb
   maxmemory-policy allkeys-lru
   ```

2. **Persistence optimization**:
   ```conf
   # For high-write workloads, consider:
   save ""  # Disable RDB snapshots
   appendonly yes
   appendfsync everysec
   ```

## Testing the Installation

1. **Start Redis** (using any method above)

2. **Test connectivity**:
   ```powershell
   ./redis-cli.exe ping
   # Should return: PONG
   ```

3. **Basic operations**:
   ```powershell
   ./redis-cli.exe
   127.0.0.1:6379> set test "Hello Redis"
   OK
   127.0.0.1:6379> get test
   "Hello Redis"
   127.0.0.1:6379> exit
   ```

## Monitoring and Logs

### Service Logs

When running as a service, check:
- **Windows Event Viewer**: Applications and Services Logs
- **Redis log file**: `redis.log` (if configured)

### Redis Info

```powershell
./redis-cli.exe info
```

### Memory Usage

```powershell
./redis-cli.exe info memory
```

## Common Issues and Solutions

### Issue: Service won't start

1. Check Windows Event Viewer for errors
2. Verify file paths in service configuration
3. Ensure `redis-server.exe` exists in the same directory
4. Check `redis.conf` syntax

### Issue: Access denied

1. Run PowerShell as Administrator
2. Check file permissions
3. Temporarily disable antivirus

### Issue: Port already in use

1. Check if another Redis instance is running:
   ```powershell
   netstat -an | findstr :6379
   ```
2. Change port in `redis.conf`:
   ```conf
   port 6380
   ```

### Issue: High memory usage

1. Set memory limits:
   ```conf
   maxmemory 1gb
   maxmemory-policy allkeys-lru
   ```

## Development and Building

### Building the Service Wrapper

```powershell
# Prerequisites: .NET 8.0 SDK
dotnet restore RedisService.csproj
dotnet publish RedisService.csproj -c Release -r win-x64 --self-contained -o publish
```

### Project Dependencies

- **Microsoft.Extensions.Hosting.WindowsServices**: For Windows service support
- **.NET 8.0**: Target framework

## Advanced Configuration

### Multiple Redis Instances

To run multiple Redis instances:

1. Create separate directories for each instance
2. Use different ports and config files:
   ```conf
   # Instance 1: redis-6379.conf
   port 6379
   pidfile ./redis-6379.pid
   logfile redis-6379.log
   
   # Instance 2: redis-6380.conf  
   port 6380
   pidfile ./redis-6380.pid
   logfile redis-6380.log
   ```

3. Install separate services:
   ```powershell
   sc.exe create Redis6379 binpath="C:\path\RedisService.exe -c C:\path\redis-6379.conf"
   sc.exe create Redis6380 binpath="C:\path\RedisService.exe -c C:\path\redis-6380.conf"
   ```

### Clustering

For Redis clustering on Windows, you'll need multiple instances. See the official Redis clustering documentation.

## Security Considerations

1. **Firewall**: Configure Windows Firewall to only allow necessary connections
2. **User Account**: Run service under a dedicated service account
3. **File Permissions**: Restrict access to Redis directory
4. **Network**: Use VPN or private networks for remote access

## Performance Monitoring

### Windows Performance Counters

Monitor these metrics:
- Process CPU usage
- Process memory usage
- Disk I/O
- Network connections

### Redis-specific Monitoring

```powershell
# Memory info
./redis-cli.exe info memory

# Connected clients
./redis-cli.exe info clients

# Statistics
./redis-cli.exe info stats
```

## Backup and Recovery

### Manual Backup

```powershell
# Copy the RDB file
copy dump.rdb backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').rdb
```

### Automated Backup Script

Create a PowerShell script for regular backups:

```powershell
# backup-redis.ps1
$backupDir = "C:\Redis\Backups"
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupFile = "$backupDir\dump_$timestamp.rdb"

# Create backup directory if it doesn't exist
if (!(Test-Path $backupDir)) {
    New-Item -ItemType Directory -Path $backupDir
}

# Trigger a background save
& redis-cli.exe BGSAVE

# Wait for save to complete, then copy file
Start-Sleep -Seconds 5
Copy-Item "dump.rdb" $backupFile

Write-Host "Backup created: $backupFile"
```

## Troubleshooting

### Enable Debug Logging

```conf
loglevel debug
logfile redis-debug.log
```

### Common Redis Commands for Diagnostics

```redis
# Check configuration
CONFIG GET *

# Monitor commands in real-time
MONITOR

# Check slow queries
SLOWLOG GET 10

# Get server info
INFO

# Check connected clients
CLIENT LIST
```

## Additional Resources

- [Official Redis Documentation](https://redis.io/documentation)
- [Redis Configuration Reference](https://redis.io/docs/manual/config/)
- [Redis Security Guide](https://redis.io/docs/manual/security/)
- [Project Repository](https://github.com/david-t-martel/redis-windows)

## License

This project follows the Redis license terms. See the LICENSE file for details.

## Contributing

Contributions are welcome! Please see the contributing guidelines in the repository.

## Disclaimer

This Windows port is intended for development and testing. For production environments, the official recommendation is to use Redis on Linux systems.
