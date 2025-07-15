@echo off
echo Redis for Windows - LLM Agent Ready
echo ====================================

REM Check if Redis server exists
if not exist "redis-server.exe" (
    echo Error: redis-server.exe not found
    echo Please download Redis binaries first:
    echo   .\build.ps1 -CheckLatestRelease
    echo   OR
    echo   .\build.ps1 -GitHubWorkflow
    pause
    exit /b 1
)

REM Check if configuration exists
if not exist "redis.conf" (
    if exist "redis-agent.conf" (
        echo Using agent-optimized configuration...
        copy "redis-agent.conf" "redis.conf" >nul
    ) else (
        echo Creating basic configuration...
        echo # Basic Redis configuration for agents > redis.conf
        echo bind 127.0.0.1 >> redis.conf
        echo port 6379 >> redis.conf
        echo save 900 1 >> redis.conf
        echo save 300 10 >> redis.conf
        echo save 60 10000 >> redis.conf
        echo maxmemory 1gb >> redis.conf
        echo maxmemory-policy allkeys-lru >> redis.conf
    )
)

echo Starting Redis server...
echo Press Ctrl+C to stop
echo.
echo Redis will be available at:
echo   Host: localhost
echo   Port: 6379
echo.
echo Test with: redis-cli.exe ping
echo.

REM Start Redis server
redis-server.exe redis.conf
