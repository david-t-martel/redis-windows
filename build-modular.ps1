# Redis for Windows - Modular Build and Setup Script
# ==================================================
# Enhanced version with separated utility modules

param(
    [switch]$DownloadBinaries,
    [switch]$BuildOnly,
    [switch]$InstallService,
    [switch]$UninstallService,
    [switch]$Help,
    [switch]$TestRedis,
    [switch]$ShowRedisInfo,
    [switch]$StartRedis,
    [switch]$StopRedis,
    [switch]$SetupUV,
    [switch]$TestUV,
    [string]$RedisPort = "6379",
    [string]$AgentMemoryPort = "8000"
)

# Import utility modules
$script:ModulesPath = Join-Path $PSScriptRoot "utilities"

Write-Host "Loading utility modules..." -ForegroundColor Cyan

# Import UV Environment module
$uvModulePath = Join-Path $script:ModulesPath "UVEnvironment.psm1"
if (Test-Path $uvModulePath) {
    Import-Module $uvModulePath -Force -Global
    Write-Host "✓ UVEnvironment module loaded" -ForegroundColor Green
}
else {
    Write-Host "✗ UVEnvironment module not found at: $uvModulePath" -ForegroundColor Red
}

# Import Redis Utilities module
$redisModulePath = Join-Path $script:ModulesPath "RedisUtilities.psm1"
if (Test-Path $redisModulePath) {
    Import-Module $redisModulePath -Force -Global
    Write-Host "✓ RedisUtilities module loaded" -ForegroundColor Green
}
else {
    Write-Host "✗ RedisUtilities module not found at: $redisModulePath" -ForegroundColor Red
}

# Helper functions
function Write-Banner {
    Write-Host ""
    Write-Host "====================================================================" -ForegroundColor Cyan
    Write-Host "Redis for Windows - Modular Build and Setup Script" -ForegroundColor Cyan
    Write-Host "====================================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Success {
    param($Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-Info {
    param($Message)
    Write-Host "[INFO] $Message" -ForegroundColor Blue
}

function Write-Warning {
    param($Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-Error {
    param($Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Test-Administrator {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Download-RedisBinaries {
    <#
    .SYNOPSIS
    Downloads Redis binaries for Windows
    
    .DESCRIPTION
    Downloads Redis server and CLI binaries from multiple sources with automatic fallback
    
    .PARAMETER DownloadPath
    Directory to download and extract Redis binaries
    
    .PARAMETER ForceDownload
    Force re-download even if binaries exist
    #>
    
    [CmdletBinding()]
    param(
        [string]$DownloadPath = (Get-Location).Path,
        [switch]$ForceDownload
    )
    
    Write-Info "Downloading Redis binaries for Windows..."
    
    # Check if Redis binaries already exist
    if (Get-Module -Name RedisUtilities) {
        $existingBinaries = Find-RedisExecutables -BasePath $DownloadPath
        if ($existingBinaries.RedisServer -and $existingBinaries.RedisCli -and -not $ForceDownload) {
            Write-Success "Redis binaries already exist:"
            Write-Host "  Redis Server: $($existingBinaries.RedisServer)" -ForegroundColor Green
            Write-Host "  Redis CLI: $($existingBinaries.RedisCli)" -ForegroundColor Green
            return $true
        }
    }
    
    # Redis download sources
    $redisDownloads = @(
        @{
            Name        = "Tporadowski Redis"
            Url         = "https://github.com/tporadowski/redis/releases/download/v5.0.14.1/Redis-x64-5.0.14.1.zip"
            Description = "Stable Redis 5.0.14.1 Windows port"
        },
        @{
            Name        = "Memurai Developer"
            Url         = "https://github.com/Memurai/memurai/releases/latest/download/Memurai-Developer.zip"
            Description = "Redis-compatible Windows binary"
        }
    )
    
    foreach ($source in $redisDownloads) {
        Write-Info "Trying source: $($source.Name)"
        Write-Info "URL: $($source.Url)"
        
        $tempDir = Join-Path $env:TEMP "redis-download-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        $zipFile = Join-Path $tempDir "redis.zip"
        
        try {
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
            
            # Try multiple download methods
            $downloadSuccess = $false
            
            # Method 1: PowerShell Invoke-WebRequest
            try {
                Write-Info "Downloading with Invoke-WebRequest..."
                Invoke-WebRequest -Uri $source.Url -OutFile $zipFile -UseBasicParsing
                if ((Test-Path $zipFile) -and (Get-Item $zipFile).Length -gt 0) {
                    $downloadSuccess = $true
                    Write-Success "Downloaded successfully"
                }
            }
            catch {
                Write-Warning "Invoke-WebRequest failed: $_"
            }
            
            # Method 2: curl (if available)
            if (-not $downloadSuccess) {
                try {
                    Write-Info "Trying curl..."
                    & curl -L -o $zipFile $source.Url
                    if ($LASTEXITCODE -eq 0 -and (Test-Path $zipFile) -and (Get-Item $zipFile).Length -gt 0) {
                        $downloadSuccess = $true
                        Write-Success "Downloaded with curl"
                    }
                }
                catch {
                    Write-Warning "curl failed: $_"
                }
            }
            
            if (-not $downloadSuccess) {
                Write-Warning "Failed to download from $($source.Name)"
                continue
            }
            
            # Extract and install
            Write-Info "Extracting Redis binaries..."
            Expand-Archive -Path $zipFile -DestinationPath $tempDir -Force
            
            # Find executables
            $foundFiles = Get-ChildItem -Path $tempDir -Recurse -File | Where-Object { 
                $_.Name -match "(redis-server|redis-cli|memurai)\.exe$" 
            }
            
            if ($foundFiles) {
                foreach ($file in $foundFiles) {
                    $targetName = $file.Name
                    # Rename memurai files to redis names
                    if ($file.Name -eq "memurai.exe") { $targetName = "redis-server.exe" }
                    if ($file.Name -eq "memurai-cli.exe") { $targetName = "redis-cli.exe" }
                    
                    $targetPath = Join-Path $DownloadPath $targetName
                    Copy-Item -Path $file.FullName -Destination $targetPath -Force
                    Write-Success "Installed: $targetName"
                }
                
                Write-Success "Redis binaries downloaded and installed successfully from $($source.Name)!"
                return $true
            }
            else {
                Write-Warning "No Redis executables found in $($source.Name) archive"
            }
        }
        catch {
            Write-Warning "Error with $($source.Name): $_"
        }
        finally {
            if (Test-Path $tempDir) {
                Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
    
    Write-Error "Failed to download Redis binaries from all sources"
    return $false
}

function Build-RedisService {
    <#
    .SYNOPSIS
    Builds the .NET Redis Windows service wrapper
    #>
    
    Write-Info "Building Redis Windows service wrapper..."
    
    if (-not (Test-Path "RedisService.csproj")) {
        Write-Error "RedisService.csproj not found in current directory"
        return $false
    }
    
    try {
        Write-Info "Building with dotnet..."
        & dotnet build RedisService.csproj -c Release
        
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Build completed successfully"
            
            # Copy output to main directory
            $outputPath = "bin\Release\net8.0\win-x64\RedisService.exe"
            if (Test-Path $outputPath) {
                Copy-Item -Path $outputPath -Destination "." -Force
                Write-Success "RedisService.exe copied to main directory"
                return $true
            }
            else {
                Write-Warning "RedisService.exe not found in expected output location"
                return $false
            }
        }
        else {
            Write-Error "Build failed with exit code: $LASTEXITCODE"
            return $false
        }
    }
    catch {
        Write-Error "Build error: $_"
        return $false
    }
}

function Show-Menu {
    Write-Host ""
    Write-Host "Redis for Windows - Modular Setup" -ForegroundColor Cyan
    Write-Host "==================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Choose an option:" -ForegroundColor Yellow
    Write-Host " 1. Download Redis binaries" -ForegroundColor White
    Write-Host " 2. Build .NET service wrapper" -ForegroundColor White
    Write-Host " 3. Test Redis setup" -ForegroundColor White
    Write-Host " 4. Show Redis information" -ForegroundColor White
    Write-Host " 5. Start Redis server" -ForegroundColor White
    Write-Host " 6. Stop Redis server" -ForegroundColor White
    Write-Host " 7. Install Redis as Windows service (admin required)" -ForegroundColor White
    Write-Host " 8. Uninstall Redis Windows service (admin required)" -ForegroundColor White
    Write-Host " 9. Setup UV environment for agents" -ForegroundColor White
    Write-Host "10. Test UV environment" -ForegroundColor White
    Write-Host "11. Full setup (download + build + test)" -ForegroundColor White
    Write-Host "12. Exit" -ForegroundColor White
    Write-Host ""
    
    $choice = Read-Host "Enter your choice (1-12)"
    return $choice
}

function Show-Help {
    Write-Host ""
    Write-Host "Redis for Windows - Modular Build Script" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "This script provides a modular approach to setting up Redis for Windows" -ForegroundColor White
    Write-Host "with enhanced support for LLM agents and development workflows." -ForegroundColor White
    Write-Host ""
    Write-Host "Command Line Parameters:" -ForegroundColor Yellow
    Write-Host "  -DownloadBinaries      Download Redis binaries automatically" -ForegroundColor Green
    Write-Host "  -BuildOnly             Build only the .NET service wrapper" -ForegroundColor Green
    Write-Host "  -InstallService        Install Redis as Windows service" -ForegroundColor Green
    Write-Host "  -UninstallService      Uninstall Redis Windows service" -ForegroundColor Green
    Write-Host "  -TestRedis             Test Redis setup and configuration" -ForegroundColor Green
    Write-Host "  -ShowRedisInfo         Display Redis installation information" -ForegroundColor Green
    Write-Host "  -StartRedis            Start Redis server" -ForegroundColor Green
    Write-Host "  -StopRedis             Stop Redis server" -ForegroundColor Green
    Write-Host "  -SetupUV               Setup UV environment for Python agents" -ForegroundColor Green
    Write-Host "  -TestUV                Test UV environment setup" -ForegroundColor Green
    Write-Host "  -Help                  Show this help message" -ForegroundColor Green
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Yellow
    Write-Host "  .\build-modular.ps1 -DownloadBinaries" -ForegroundColor Cyan
    Write-Host "  .\build-modular.ps1 -StartRedis" -ForegroundColor Cyan
    Write-Host "  .\build-modular.ps1 -SetupUV" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Features:" -ForegroundColor Yellow
    Write-Host "  • Modular PowerShell architecture" -ForegroundColor Green
    Write-Host "  • Automatic Redis binary download from multiple sources" -ForegroundColor Green
    Write-Host "  • UV environment management for Python agents" -ForegroundColor Green
    Write-Host "  • Redis service management (start/stop/install)" -ForegroundColor Green
    Write-Host "  • Agent-optimized Redis configuration" -ForegroundColor Green
    Write-Host ""
}

# Main script execution
Write-Banner

# Handle command line parameters
if ($Help) {
    Show-Help
    exit 0
}

if ($DownloadBinaries) {
    $result = Download-RedisBinaries
    exit $(if ($result) { 0 } else { 1 })
}

if ($BuildOnly) {
    $result = Build-RedisService
    exit $(if ($result) { 0 } else { 1 })
}

if ($TestRedis) {
    if (Get-Module -Name RedisUtilities) {
        $result = Test-RedisSetup
        exit $(if ($result) { 0 } else { 1 })
    }
    else {
        Write-Error "RedisUtilities module not loaded"
        exit 1
    }
}

if ($ShowRedisInfo) {
    if (Get-Module -Name RedisUtilities) {
        Show-RedisInfo
    }
    else {
        Write-Error "RedisUtilities module not loaded"
    }
    exit 0
}

if ($StartRedis) {
    if (Get-Module -Name RedisUtilities) {
        $configPath = if (Test-Path "redis-agent.conf") { "redis-agent.conf" } else { "redis.conf" }
        $result = Start-RedisServer -ConfigPath $configPath
        exit $(if ($result) { 0 } else { 1 })
    }
    else {
        Write-Error "RedisUtilities module not loaded"
        exit 1
    }
}

if ($StopRedis) {
    if (Get-Module -Name RedisUtilities) {
        $result = Stop-RedisServer
        exit $(if ($result) { 0 } else { 1 })
    }
    else {
        Write-Error "RedisUtilities module not loaded"
        exit 1
    }
}

if ($InstallService) {
    if (-not (Test-Administrator)) {
        Write-Error "Administrator privileges required for service installation"
        exit 1
    }
    
    if (Get-Module -Name RedisUtilities) {
        $configPath = if (Test-Path "redis-agent.conf") { "redis-agent.conf" } else { "redis.conf" }
        $result = Install-RedisService -ConfigPath $configPath
        exit $(if ($result) { 0 } else { 1 })
    }
    else {
        Write-Error "RedisUtilities module not loaded"
        exit 1
    }
}

if ($UninstallService) {
    if (-not (Test-Administrator)) {
        Write-Error "Administrator privileges required for service removal"
        exit 1
    }
    
    if (Get-Module -Name RedisUtilities) {
        $result = Uninstall-RedisService
        exit $(if ($result) { 0 } else { 1 })
    }
    else {
        Write-Error "RedisUtilities module not loaded"
        exit 1
    }
}

if ($SetupUV) {
    if (Get-Module -Name UVEnvironment) {
        $result = Initialize-UVEnvironment
        if ($result) {
            Show-UVEnvironmentInfo
        }
        exit $(if ($result) { 0 } else { 1 })
    }
    else {
        Write-Error "UVEnvironment module not loaded"
        exit 1
    }
}

if ($TestUV) {
    if (Get-Module -Name UVEnvironment) {
        $result = Test-UVEnvironment
        exit $(if ($result) { 0 } else { 1 })
    }
    else {
        Write-Error "UVEnvironment module not loaded"
        exit 1
    }
}

# Interactive menu if no parameters provided
Write-Host "No parameters provided. Starting interactive mode..." -ForegroundColor Yellow

if (-not (Test-Administrator)) {
    Write-Warning "Not running as administrator - service installation will not be available"
}

do {
    $choice = Show-Menu
    
    switch ($choice) {
        "1" { 
            Download-RedisBinaries
        }
        "2" { 
            Build-RedisService
        }
        "3" { 
            if (Get-Module -Name RedisUtilities) {
                Test-RedisSetup
            }
            else {
                Write-Error "RedisUtilities module not loaded"
            }
        }
        "4" {
            if (Get-Module -Name RedisUtilities) {
                Show-RedisInfo
            }
            else {
                Write-Error "RedisUtilities module not loaded"
            }
        }
        "5" {
            if (Get-Module -Name RedisUtilities) {
                $configPath = if (Test-Path "redis-agent.conf") { "redis-agent.conf" } else { "redis.conf" }
                Start-RedisServer -ConfigPath $configPath
            }
            else {
                Write-Error "RedisUtilities module not loaded"
            }
        }
        "6" {
            if (Get-Module -Name RedisUtilities) {
                Stop-RedisServer
            }
            else {
                Write-Error "RedisUtilities module not loaded"
            }
        }
        "7" {
            if (Test-Administrator) {
                if (Get-Module -Name RedisUtilities) {
                    $configPath = if (Test-Path "redis-agent.conf") { "redis-agent.conf" } else { "redis.conf" }
                    Install-RedisService -ConfigPath $configPath
                }
                else {
                    Write-Error "RedisUtilities module not loaded"
                }
            }
            else {
                Write-Error "Administrator privileges required for service installation"
            }
        }
        "8" {
            if (Test-Administrator) {
                if (Get-Module -Name RedisUtilities) {
                    Uninstall-RedisService
                }
                else {
                    Write-Error "RedisUtilities module not loaded"
                }
            }
            else {
                Write-Error "Administrator privileges required for service removal"
            }
        }
        "9" {
            if (Get-Module -Name UVEnvironment) {
                $result = Initialize-UVEnvironment
                if ($result) {
                    Show-UVEnvironmentInfo
                }
            }
            else {
                Write-Error "UVEnvironment module not loaded"
            }
        }
        "10" {
            if (Get-Module -Name UVEnvironment) {
                Test-UVEnvironment
            }
            else {
                Write-Error "UVEnvironment module not loaded"
            }
        }
        "11" {
            Write-Info "Starting full setup process..."
            
            # Step 1: Download binaries
            Write-Info "Step 1: Downloading Redis binaries..."
            $downloadResult = Download-RedisBinaries
            
            if ($downloadResult) {
                # Step 2: Build service
                Write-Info "Step 2: Building .NET service wrapper..."
                $buildResult = Build-RedisService
                
                if ($buildResult) {
                    # Step 3: Test setup
                    Write-Info "Step 3: Testing Redis setup..."
                    if (Get-Module -Name RedisUtilities) {
                        Test-RedisSetup
                        Show-RedisInfo
                    }
                    
                    Write-Success "Full setup completed successfully!"
                    Write-Host ""
                    Write-Host "Next steps:" -ForegroundColor Cyan
                    Write-Host "• Start Redis: .\build-modular.ps1 -StartRedis" -ForegroundColor Yellow
                    Write-Host "• Install as service: .\build-modular.ps1 -InstallService (as admin)" -ForegroundColor Yellow
                    Write-Host "• Setup UV environment: .\build-modular.ps1 -SetupUV" -ForegroundColor Yellow
                }
                else {
                    Write-Error "Build failed - full setup incomplete"
                }
            }
            else {
                Write-Error "Download failed - full setup incomplete"
            }
        }
        "12" { 
            break 
        }
        default { 
            Write-Warning "Invalid choice. Please select 1-12." 
        }
    }
    
    if ($choice -ne "12") {
        Read-Host "`nPress Enter to continue..."
    }
} while ($choice -ne "12")

Write-Host ""
Write-Host "Thank you for using Redis for Windows!" -ForegroundColor Cyan
Write-Host ""
