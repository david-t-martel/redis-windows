# Redis for Windows - Quick Start Guide

## TL;DR - Get Redis Running in 5 Minutes

### Option 1: Use Pre-built Binaries (Recommended)

1. **Download the latest release:**
   - Go to: https://github.com/david-t-martel/redis-windows/releases
   - Download: `Redis-X.X.X-Windows-x64-with-Service.zip`
   - Extract to any folder (e.g., `C:\Redis`)

2. **Quick Test:**
   ```cmd
   # Navigate to Redis folder
   cd C:\Redis
   
   # Start Redis (one-click)
   start.bat
   
   # In another terminal, test it
   redis-cli.exe ping
   # Should return: PONG
   ```

3. **Install as Service (Optional):**
   ```powershell
   # Run as Administrator
   sc.exe create Redis binpath="C:\Redis\RedisService.exe" start=auto
   net start Redis
   ```

### Option 2: Build from Source

1. **Prerequisites:**
   - .NET 8.0 SDK
   - PowerShell (recommended) or Command Prompt

2. **Build:**
   ```powershell
   # Clone or download this repository
   cd redis-windows
   
   # Run the build script
   .\build.ps1
   # Follow the interactive prompts
   ```

3. **Get Redis Binaries:**
   Since the actual Redis server needs to be compiled, you'll need:
   - Download from releases (easiest)
   - Or trigger the GitHub Actions workflow to build from source

## What You Get

After setup, you'll have:

- `redis-server.exe` - The Redis server
- `redis-cli.exe` - Command line client  
- `RedisService.exe` - Windows service wrapper
- `redis.conf` - Configuration file
- `start.bat` - Quick start script

## Basic Usage

### Start Redis
```powershell
# Option 1: Direct execution
.\redis-server.exe redis.conf

# Option 2: One-click startup
.\start.bat

# Option 3: As Windows service
net start Redis
```

### Basic Commands
```powershell
# Test connection
.\redis-cli.exe ping

# Set a value
.\redis-cli.exe set mykey "Hello Redis"

# Get a value  
.\redis-cli.exe get mykey

# List all keys
.\redis-cli.exe keys *

# Get server info
.\redis-cli.exe info
```

### Stop Redis
```powershell
# If running directly (Ctrl+C or)
.\redis-cli.exe shutdown

# If running as service
net stop Redis
```

## Common Use Cases

### Development Environment
```powershell
# Start Redis for development
.\start.bat

# Your app connects to: localhost:6379
# Default: no password, 16 databases (0-15)
```

### Production Service
```powershell
# Install as service (run as Administrator)
sc.exe create Redis binpath="C:\path\to\RedisService.exe" start=auto
net start Redis

# Configure for production in redis.conf:
# - Set a password: requirepass your_password
# - Bind to specific IP: bind 127.0.0.1 192.168.1.100  
# - Set memory limit: maxmemory 2gb
```

### Multiple Instances
```powershell
# Create separate folders with different configs
# Use different ports in each redis.conf:
# Instance 1: port 6379
# Instance 2: port 6380

# Install separate services
sc.exe create Redis6379 binpath="C:\Redis1\RedisService.exe -c C:\Redis1\redis.conf"
sc.exe create Redis6380 binpath="C:\Redis2\RedisService.exe -c C:\Redis2\redis.conf"
```

## Configuration Highlights

Key settings in `redis.conf`:

```conf
# Network
bind 127.0.0.1          # Listen on localhost only
port 6379               # Default Redis port

# Security  
# requirepass mypassword # Uncomment to set password

# Memory
maxmemory 256mb         # Set memory limit
maxmemory-policy allkeys-lru

# Persistence
save 900 1              # Save if 1 key changes in 15 min
save 300 10             # Save if 10 keys change in 5 min
save 60 10000           # Save if 10k keys change in 1 min

# Logging
loglevel notice         # info, warning, debug
logfile redis.log       # Log to file
```

## Troubleshooting

### Redis won't start
```powershell
# Check if port is in use
netstat -an | findstr :6379

# Check Redis log
type redis.log

# Test config file
.\redis-server.exe --test-config redis.conf
```

### Service won't start
```powershell
# Check Windows Event Viewer:
# Windows Logs > Application
# Look for "Redis Service" entries

# Verify service path
sc.exe qc Redis

# Check file permissions and paths
```

### Can't connect
```powershell
# Verify Redis is running
.\redis-cli.exe ping

# Check if password is required
.\redis-cli.exe -a yourpassword ping

# Check connection to different port
.\redis-cli.exe -p 6380 ping
```

### High memory usage
```conf
# Add to redis.conf:
maxmemory 1gb
maxmemory-policy allkeys-lru
```

## Performance Tips

1. **Memory Management:**
   ```conf
   maxmemory 2gb
   maxmemory-policy allkeys-lru
   ```

2. **Persistence Tuning:**
   ```conf
   # For high-write loads, consider:
   save ""                    # Disable RDB snapshots
   appendonly yes             # Enable AOF
   appendfsync everysec       # AOF sync every second
   ```

3. **Network Optimization:**
   ```conf
   tcp-keepalive 60
   timeout 300
   ```

## Security Checklist

- [ ] Set a strong password: `requirepass your_strong_password`
- [ ] Bind to specific interfaces: `bind 127.0.0.1 192.168.1.100`
- [ ] Disable dangerous commands: `rename-command FLUSHALL ""`
- [ ] Configure Windows Firewall
- [ ] Use TLS if needed (Redis 6.0+)
- [ ] Run service under dedicated user account
- [ ] Backup regularly

## Need Help?

- **Documentation:** See `SETUP_GUIDE.md` for complete details
- **Issues:** https://github.com/david-t-martel/redis-windows/issues
- **Redis Docs:** https://redis.io/documentation
- **Windows Event Viewer:** For service debugging

## What's Next?

1. **Learn Redis:** https://redis.io/learn
2. **Redis CLI Guide:** https://redis.io/docs/ui/cli/
3. **Configuration Reference:** https://redis.io/docs/manual/config/
4. **Production Deployment:** See `SETUP_GUIDE.md`

---

*Redis for Windows is a community project. For production use, consider the official recommendation to use Redis on Linux systems.*
