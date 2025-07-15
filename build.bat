@echo off
REM ===================================================================
REM Redis for Windows - Build and Setup Script
REM ===================================================================

setlocal enabledelayedexpansion

echo ===================================================================
echo Redis for Windows - Build and Setup Script
echo ===================================================================
echo.

REM Check if running as administrator
net session >nul 2>&1
if %errorLevel% == 0 (
    echo [INFO] Running with administrator privileges
) else (
    echo [WARNING] Not running as administrator - service installation will fail
)

echo.
echo Choose an option:
echo 1. Download latest Redis binaries from GitHub releases
echo 2. Build .NET service wrapper only
echo 3. Full setup (download + configure)
echo 4. Install as Windows service
echo 5. Exit
echo.

set /p choice="Enter your choice (1-5): "

if "%choice%"=="1" goto :download_binaries
if "%choice%"=="2" goto :build_service
if "%choice%"=="3" goto :full_setup
if "%choice%"=="4" goto :install_service
if "%choice%"=="5" goto :exit
goto :invalid_choice

:download_binaries
echo.
echo [INFO] Downloading latest Redis binaries...
echo.

REM Try to get the latest release version
set "GITHUB_API=https://api.github.com/repos/redis/redis/releases/latest"
set "REDIS_VERSION=7.2.4"

echo [INFO] Downloading Redis %REDIS_VERSION% for Windows...
echo.
echo Note: The actual Redis binaries need to be built using the GitHub Actions workflow.
echo This would download from: https://github.com/david-t-martel/redis-windows/releases
echo.
echo For now, please:
echo 1. Go to https://github.com/david-t-martel/redis-windows/releases
echo 2. Download the latest Redis-X.X.X-Windows-x64-with-Service.zip
echo 3. Extract it to this directory
echo.
pause
goto :build_service

:build_service
echo.
echo [INFO] Building .NET Redis service wrapper...
echo.

REM Check if .NET SDK is available
dotnet --version >nul 2>&1
if %errorLevel% neq 0 (
    echo [ERROR] .NET SDK not found. Please install .NET 8.0 SDK.
    echo Download from: https://dotnet.microsoft.com/download
    pause
    goto :exit
)

echo [INFO] Found .NET SDK
dotnet --version

echo.
echo [INFO] Restoring NuGet packages...
dotnet restore RedisService.csproj
if %errorLevel% neq 0 (
    echo [ERROR] Failed to restore packages
    pause
    goto :exit
)

echo.
echo [INFO] Building Redis service...
dotnet publish RedisService.csproj -c Release -r win-x64 --self-contained -o publish
if %errorLevel% neq 0 (
    echo [ERROR] Failed to build service
    pause
    goto :exit
)

echo.
echo [SUCCESS] Service built successfully!
echo Output: .\publish\RedisService.exe

REM Copy the service executable to the main directory
if exist ".\publish\RedisService.exe" (
    copy ".\publish\RedisService.exe" ".\RedisService.exe" >nul
    echo [INFO] Copied RedisService.exe to main directory
)

goto :check_redis_binaries

:check_redis_binaries
echo.
echo [INFO] Checking for Redis binaries...

if not exist "redis-server.exe" (
    echo.
    echo [WARNING] redis-server.exe not found!
    echo.
    echo To get Redis binaries, you need to either:
    echo 1. Download from GitHub releases (see SETUP_GUIDE.md)
    echo 2. Use the GitHub Actions workflow to build them
    echo 3. Build them manually using MSYS2 or Cygwin
    echo.
    echo The service wrapper is ready, but you need redis-server.exe to run Redis.
    pause
    goto :exit
)

echo [SUCCESS] Found redis-server.exe
if exist "redis-cli.exe" echo [SUCCESS] Found redis-cli.exe

goto :test_setup

:full_setup
call :download_binaries
call :build_service
call :test_setup
goto :ask_service_install

:test_setup
echo.
echo [INFO] Testing Redis setup...

if not exist "redis.conf" (
    echo [WARNING] redis.conf not found - using default configuration
)

if exist "redis-server.exe" (
    echo.
    echo [INFO] Testing Redis server startup...
    echo [INFO] This will start Redis briefly to test the configuration
    
    start /B redis-server.exe redis.conf
    timeout /t 3 >nul
    
    if exist "redis-cli.exe" (
        echo [INFO] Testing Redis connectivity...
        redis-cli.exe ping
        if %errorLevel% equ 0 (
            echo [SUCCESS] Redis is responding to ping
        ) else (
            echo [WARNING] Redis not responding - check configuration
        )
        
        REM Stop the test instance
        redis-cli.exe shutdown nosave 2>nul
    ) else (
        echo [WARNING] redis-cli.exe not found - cannot test connectivity
        REM Try to stop manually
        taskkill /IM redis-server.exe /F >nul 2>&1
    )
) else (
    echo [ERROR] Cannot test - redis-server.exe not found
)

goto :ask_service_install

:ask_service_install
echo.
set /p install_svc="Do you want to install Redis as a Windows service? (y/n): "
if /i "%install_svc%"=="y" goto :install_service
if /i "%install_svc%"=="yes" goto :install_service
goto :setup_complete

:install_service
echo.
echo [INFO] Installing Redis as Windows service...

REM Check if service already exists
sc query Redis >nul 2>&1
if %errorLevel% equ 0 (
    echo [WARNING] Redis service already exists
    set /p reinstall="Do you want to reinstall it? (y/n): "
    if /i "!reinstall!"=="y" (
        echo [INFO] Stopping and removing existing service...
        net stop Redis >nul 2>&1
        sc delete Redis >nul 2>&1
        timeout /t 2 >nul
    ) else (
        goto :setup_complete
    )
)

REM Get current directory
set "CURRENT_DIR=%~dp0"
set "SERVICE_PATH=%CURRENT_DIR%RedisService.exe"
set "CONFIG_PATH=%CURRENT_DIR%redis.conf"

echo [INFO] Service path: %SERVICE_PATH%
echo [INFO] Config path: %CONFIG_PATH%

if not exist "%SERVICE_PATH%" (
    echo [ERROR] RedisService.exe not found at %SERVICE_PATH%
    echo Please run option 2 first to build the service
    pause
    goto :exit
)

REM Create the service
echo [INFO] Creating Redis service...
if exist "%CONFIG_PATH%" (
    sc create Redis binpath="\"%SERVICE_PATH%\" -c \"%CONFIG_PATH%\"" start=auto DisplayName="Redis Server"
) else (
    sc create Redis binpath="\"%SERVICE_PATH%\"" start=auto DisplayName="Redis Server"
)

if %errorLevel% neq 0 (
    echo [ERROR] Failed to create service
    echo Make sure you are running as administrator
    pause
    goto :exit
)

echo [SUCCESS] Service created successfully!

REM Try to start the service
echo [INFO] Starting Redis service...
net start Redis
if %errorLevel% equ 0 (
    echo [SUCCESS] Redis service started successfully!
    
    REM Test the service
    timeout /t 3 >nul
    if exist "redis-cli.exe" (
        echo [INFO] Testing service...
        redis-cli.exe ping
        if %errorLevel% equ 0 (
            echo [SUCCESS] Redis service is running and responding!
        )
    )
) else (
    echo [ERROR] Failed to start service
    echo Check Windows Event Viewer for error details
)

goto :setup_complete

:setup_complete
echo.
echo ===================================================================
echo Setup Complete!
echo ===================================================================
echo.
echo What's available:
if exist "RedisService.exe" echo   ✓ Redis Windows Service Wrapper
if exist "redis-server.exe" echo   ✓ Redis Server Binary
if exist "redis-cli.exe" echo   ✓ Redis CLI Client
if exist "redis.conf" echo   ✓ Redis Configuration File
echo.

echo Usage:
echo   Direct:     start.bat
echo   CLI:        redis-server.exe redis.conf
echo   Service:    net start Redis
echo.

if exist "redis-cli.exe" (
    echo Test Redis:
    echo   redis-cli.exe ping
    echo   redis-cli.exe set test "Hello Redis"
    echo   redis-cli.exe get test
    echo.
)

echo For detailed documentation, see SETUP_GUIDE.md
echo.
pause
goto :exit

:invalid_choice
echo.
echo [ERROR] Invalid choice. Please select 1-5.
echo.
pause
goto :exit

:exit
echo.
echo Goodbye!
endlocal
