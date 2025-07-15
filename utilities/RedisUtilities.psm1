# RedisUtilities.psm1
# ====================
# PowerShell module for Redis Windows management utilities
# Provides Redis server management, service operations, and configuration

#Requires -Version 5.1

# Module variables
$script:ModuleVersion = "1.0.0"
$script:RedisServerPath = $null
$script:RedisCliPath = $null
$script:RedisServicePath = $null

# Export module information
$ModuleInfo = @{
    Version     = $script:ModuleVersion
    Description = "Redis for Windows Management Utilities"
    Author      = "Redis for Windows Project"
    CompanyName = "Redis Windows"
}

# Utility Functions
function Write-RedisInfo {
    param([string]$Message)
    Write-Host "[REDIS-INFO] $Message" -ForegroundColor Blue
}

function Write-RedisSuccess {
    param([string]$Message)
    Write-Host "[REDIS-SUCCESS] $Message" -ForegroundColor Green
}

function Write-RedisWarning {
    param([string]$Message)
    Write-Host "[REDIS-WARNING] $Message" -ForegroundColor Yellow
}

function Write-RedisError {
    param([string]$Message)
    Write-Host "[REDIS-ERROR] $Message" -ForegroundColor Red
}

function Find-RedisExecutables {
    <#
    .SYNOPSIS
    Locates Redis executables in the project directory
    
    .DESCRIPTION
    Searches for redis-server.exe, redis-cli.exe, and RedisService.exe in various locations
    
    .PARAMETER BasePath
    Base directory to search from. Defaults to current directory
    
    .OUTPUTS
    Hashtable with paths to found executables
    #>
    
    [CmdletBinding()]
    param(
        [string]$BasePath = (Get-Location).Path
    )
    
    Write-RedisInfo "Searching for Redis executables in: $BasePath"
    
    $executables = @{
        RedisServer  = $null
        RedisCli     = $null
        RedisService = $null
    }
    
    # Search patterns and locations
    $searchPaths = @(
        $BasePath,
        (Join-Path $BasePath "bin"),
        (Join-Path $BasePath "redis"),
        (Join-Path $BasePath "build"),
        (Join-Path $BasePath "publish")
    )
    
    $executablePatterns = @{
        RedisServer  = @("redis-server.exe", "redis-server")
        RedisCli     = @("redis-cli.exe", "redis-cli")
        RedisService = @("RedisService.exe")
    }
    
    foreach ($searchPath in $searchPaths) {
        if (Test-Path $searchPath) {
            foreach ($exeType in $executablePatterns.Keys) {
                if ($executables[$exeType]) { continue }  # Already found
                
                foreach ($pattern in $executablePatterns[$exeType]) {
                    $fullPath = Join-Path $searchPath $pattern
                    if (Test-Path $fullPath) {
                        $executables[$exeType] = $fullPath
                        Write-RedisSuccess "Found $exeType at: $fullPath"
                        break
                    }
                }
            }
        }
    }
    
    # Search recursively if not found
    foreach ($exeType in $executablePatterns.Keys) {
        if (-not $executables[$exeType]) {
            foreach ($pattern in $executablePatterns[$exeType]) {
                try {
                    $found = Get-ChildItem -Path $BasePath -Filter $pattern -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($found) {
                        $executables[$exeType] = $found.FullName
                        Write-RedisSuccess "Found $exeType at: $($found.FullName)"
                        break
                    }
                }
                catch {
                    # Continue searching
                }
            }
        }
    }
    
    # Update script variables
    $script:RedisServerPath = $executables.RedisServer
    $script:RedisCliPath = $executables.RedisCli
    $script:RedisServicePath = $executables.RedisService
    
    return $executables
}

function Test-RedisSetup {
    <#
    .SYNOPSIS
    Tests Redis installation and configuration
    
    .DESCRIPTION
    Checks for Redis executables, configuration files, and service status
    
    .PARAMETER BasePath
    Base directory for Redis installation
    
    .OUTPUTS
    Hashtable with setup status information
    #>
    
    [CmdletBinding()]
    param(
        [string]$BasePath = (Get-Location).Path
    )
    
    Write-RedisInfo "Testing Redis setup..."
    
    $executables = Find-RedisExecutables -BasePath $BasePath
    
    $status = @{
        RedisServer        = [bool]$executables.RedisServer
        RedisCli           = [bool]$executables.RedisCli
        RedisService       = [bool]$executables.RedisService
        Configuration      = (Test-Path (Join-Path $BasePath "redis.conf"))
        AgentConfiguration = (Test-Path (Join-Path $BasePath "redis-agent.conf"))
        ServiceInstalled   = $false
    }
    
    # Check if service is installed
    try {
        $service = Get-Service -Name "Redis" -ErrorAction SilentlyContinue
        $status.ServiceInstalled = [bool]$service
    }
    catch {
        $status.ServiceInstalled = $false
    }
    
    # Display status
    Write-Host ""
    Write-Host "Redis Setup Status:" -ForegroundColor Cyan
    Write-Host "  Redis Server:      $(if($status.RedisServer){'✓'}else{'✗'})" -ForegroundColor $(if ($status.RedisServer) { 'Green' }else { 'Red' })
    Write-Host "  Redis CLI:         $(if($status.RedisCli){'✓'}else{'✗'})" -ForegroundColor $(if ($status.RedisCli) { 'Green' }else { 'Red' })
    Write-Host "  Redis Service:     $(if($status.RedisService){'✓'}else{'✗'})" -ForegroundColor $(if ($status.RedisService) { 'Green' }else { 'Red' })
    Write-Host "  Configuration:     $(if($status.Configuration){'✓'}else{'✗'})" -ForegroundColor $(if ($status.Configuration) { 'Green' }else { 'Red' })
    Write-Host "  Agent Config:      $(if($status.AgentConfiguration){'✓'}else{'✗'})" -ForegroundColor $(if ($status.AgentConfiguration) { 'Green' }else { 'Red' })
    Write-Host "  Service Installed: $(if($status.ServiceInstalled){'✓'}else{'✗'})" -ForegroundColor $(if ($status.ServiceInstalled) { 'Green' }else { 'Red' })
    Write-Host ""
    
    return $status
}

function Start-RedisServer {
    <#
    .SYNOPSIS
    Starts Redis server directly (not as service)
    
    .DESCRIPTION
    Launches Redis server with specified configuration for testing purposes
    
    .PARAMETER ConfigPath
    Path to Redis configuration file
    
    .PARAMETER RedisServerPath
    Path to redis-server.exe
    
    .PARAMETER Background
    Whether to run in background
    
    .OUTPUTS
    Process object if started successfully
    #>
    
    [CmdletBinding()]
    param(
        [string]$ConfigPath = "redis.conf",
        [string]$RedisServerPath = $script:RedisServerPath,
        [switch]$Background
    )
    
    if (-not $RedisServerPath -or -not (Test-Path $RedisServerPath)) {
        Write-RedisError "Redis server executable not found: $RedisServerPath"
        return $null
    }
    
    if (-not (Test-Path $ConfigPath)) {
        Write-RedisWarning "Configuration file not found: $ConfigPath"
        Write-RedisInfo "Starting Redis with default configuration"
        $ConfigPath = $null
    }
    
    Write-RedisInfo "Starting Redis server..."
    
    try {
        $processArgs = @{
            FilePath = $RedisServerPath
            PassThru = $true
        }
        
        if ($ConfigPath) {
            $processArgs.ArgumentList = $ConfigPath
        }
        
        if ($Background) {
            $processArgs.WindowStyle = "Hidden"
        }
        
        $redisProcess = Start-Process @processArgs
        
        # Wait a moment to check if it started successfully
        Start-Sleep -Seconds 2
        
        if (-not $redisProcess.HasExited) {
            Write-RedisSuccess "Redis server started (PID: $($redisProcess.Id))"
            return $redisProcess
        }
        else {
            Write-RedisError "Redis server failed to start"
            return $null
        }
    }
    catch {
        Write-RedisError "Failed to start Redis server: $_"
        return $null
    }
}

function Stop-RedisServer {
    <#
    .SYNOPSIS
    Stops Redis server gracefully
    
    .DESCRIPTION
    Attempts to shutdown Redis server using redis-cli or process termination
    
    .PARAMETER RedisCliPath
    Path to redis-cli.exe
    
    .PARAMETER ProcessId
    Process ID of Redis server to stop
    
    .PARAMETER Force
    Force termination if graceful shutdown fails
    #>
    
    [CmdletBinding()]
    param(
        [string]$RedisCliPath = $script:RedisCliPath,
        [int]$ProcessId,
        [switch]$Force
    )
    
    Write-RedisInfo "Stopping Redis server..."
    
    # Try graceful shutdown with redis-cli
    if ($RedisCliPath -and (Test-Path $RedisCliPath)) {
        try {
            Write-RedisInfo "Attempting graceful shutdown with redis-cli"
            & $RedisCliPath shutdown nosave 2>$null
            Start-Sleep -Seconds 2
            Write-RedisSuccess "Redis server stopped gracefully"
            return $true
        }
        catch {
            Write-RedisWarning "Graceful shutdown failed: $_"
        }
    }
    
    # Try process termination
    if ($ProcessId) {
        try {
            $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
            if ($process) {
                if ($Force) {
                    Stop-Process -Id $ProcessId -Force
                }
                else {
                    $process.CloseMainWindow()
                    Start-Sleep -Seconds 3
                    if (-not $process.HasExited) {
                        Stop-Process -Id $ProcessId -Force
                    }
                }
                Write-RedisSuccess "Redis server process terminated"
                return $true
            }
        }
        catch {
            Write-RedisError "Failed to stop Redis process: $_"
        }
    }
    
    return $false
}

function Test-RedisConnection {
    <#
    .SYNOPSIS
    Tests Redis server connectivity
    
    .DESCRIPTION
    Attempts to connect to Redis server and verify it's responding
    
    .PARAMETER RedisCliPath
    Path to redis-cli.exe
    
    .PARAMETER Host
    Redis server host
    
    .PARAMETER Port
    Redis server port
    
    .OUTPUTS
    Boolean indicating successful connection
    #>
    
    [CmdletBinding()]
    param(
        [string]$RedisCliPath = $script:RedisCliPath,
        [string]$Host = "localhost",
        [int]$Port = 6379
    )
    
    if (-not $RedisCliPath -or -not (Test-Path $RedisCliPath)) {
        Write-RedisWarning "Redis CLI not available for connection test"
        return $false
    }
    
    Write-RedisInfo "Testing Redis connection to ${Host}:${Port}..."
    
    try {
        $pingResult = & $RedisCliPath -h $Host -p $Port ping 2>$null
        if ($pingResult -eq "PONG") {
            Write-RedisSuccess "Redis is responding to ping commands"
            return $true
        }
        else {
            Write-RedisWarning "Redis not responding to ping"
            return $false
        }
    }
    catch {
        Write-RedisError "Failed to test Redis connection: $_"
        return $false
    }
}

function Install-RedisService {
    <#
    .SYNOPSIS
    Installs Redis as a Windows service
    
    .DESCRIPTION
    Creates and installs the Redis Windows service using the RedisService.exe wrapper
    
    .PARAMETER ServicePath
    Path to RedisService.exe
    
    .PARAMETER ConfigPath
    Path to Redis configuration file
    
    .PARAMETER ServiceName
    Name for the Windows service
    
    .PARAMETER StartupType
    Service startup type (Auto, Manual, Disabled)
    
    .OUTPUTS
    Boolean indicating successful installation
    #>
    
    [CmdletBinding()]
    param(
        [string]$ServicePath = $script:RedisServicePath,
        [string]$ConfigPath = "redis.conf",
        [string]$ServiceName = "Redis",
        [string]$StartupType = "auto"
    )
    
    # Check administrator privileges
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-RedisError "Administrator privileges required to install Windows service"
        return $false
    }
    
    if (-not $ServicePath -or -not (Test-Path $ServicePath)) {
        Write-RedisError "Redis service executable not found: $ServicePath"
        return $false
    }
    
    Write-RedisInfo "Installing Redis as Windows service..."
    
    # Check if service already exists
    $existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($existingService) {
        Write-RedisWarning "Service '$ServiceName' already exists"
        $replace = Read-Host "Replace existing service? (y/n)"
        if ($replace -match '^y') {
            Uninstall-RedisService -ServiceName $ServiceName
        }
        else {
            return $false
        }
    }
    
    # Build service command
    $binPath = "`"$ServicePath`""
    if ($ConfigPath -and (Test-Path $ConfigPath)) {
        $configFullPath = Resolve-Path $ConfigPath
        $binPath += " -c `"$configFullPath`""
    }
    
    Write-RedisInfo "Creating service with command: $binPath"
    
    try {
        $createResult = & sc.exe create $ServiceName binpath= $binPath start= $StartupType DisplayName= "Redis Server" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-RedisSuccess "Redis service installed successfully"
            
            # Try to start the service
            Write-RedisInfo "Starting Redis service..."
            try {
                Start-Service -Name $ServiceName -ErrorAction Stop
                Write-RedisSuccess "Redis service started successfully"
                
                # Test the service
                Start-Sleep -Seconds 3
                $connectionTest = Test-RedisConnection
                if ($connectionTest) {
                    Write-RedisSuccess "Redis service is running and responding!"
                }
                
                return $true
            }
            catch {
                Write-RedisError "Failed to start service: $_"
                Write-RedisInfo "Check Windows Event Viewer for detailed error information"
                return $false
            }
        }
        else {
            Write-RedisError "Failed to create service: $createResult"
            return $false
        }
    }
    catch {
        Write-RedisError "Error installing Redis service: $_"
        return $false
    }
}

function Uninstall-RedisService {
    <#
    .SYNOPSIS
    Uninstalls Redis Windows service
    
    .DESCRIPTION
    Stops and removes the Redis Windows service
    
    .PARAMETER ServiceName
    Name of the service to remove
    
    .OUTPUTS
    Boolean indicating successful removal
    #>
    
    [CmdletBinding()]
    param(
        [string]$ServiceName = "Redis"
    )
    
    # Check administrator privileges
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-RedisError "Administrator privileges required to uninstall Windows service"
        return $false
    }
    
    Write-RedisInfo "Uninstalling Redis service..."
    
    # Stop service if running
    try {
        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
        Write-RedisInfo "Stopped Redis service"
    }
    catch {
        # Service might not exist or already stopped
    }
    
    # Delete service
    try {
        $deleteResult = & sc.exe delete $ServiceName 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-RedisSuccess "Redis service uninstalled successfully"
            return $true
        }
        else {
            Write-RedisError "Failed to delete service: $deleteResult"
            return $false
        }
    }
    catch {
        Write-RedisError "Error uninstalling Redis service: $_"
        return $false
    }
}

function Get-RedisServiceStatus {
    <#
    .SYNOPSIS
    Gets Redis service status information
    
    .DESCRIPTION
    Retrieves detailed status information about the Redis Windows service
    
    .PARAMETER ServiceName
    Name of the Redis service
    
    .OUTPUTS
    Hashtable with service status information
    #>
    
    [CmdletBinding()]
    param(
        [string]$ServiceName = "Redis"
    )
    
    $status = @{
        Exists    = $false
        Status    = $null
        StartType = $null
        ProcessId = $null
        CanStop   = $false
        CanPause  = $false
    }
    
    try {
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($service) {
            $status.Exists = $true
            $status.Status = $service.Status
            $status.StartType = $service.StartType
            $status.CanStop = $service.CanStop
            $status.CanPause = $service.CanPauseAndContinue
            
            # Get process ID if running
            if ($service.Status -eq "Running") {
                $process = Get-WmiObject -Class Win32_Service -Filter "Name='$ServiceName'" | Select-Object ProcessId
                $status.ProcessId = $process.ProcessId
            }
        }
    }
    catch {
        Write-RedisWarning "Error getting service status: $_"
    }
    
    return $status
}

function Show-RedisInfo {
    <#
    .SYNOPSIS
    Displays comprehensive Redis installation information
    
    .DESCRIPTION
    Shows Redis executable locations, service status, and configuration details
    
    .PARAMETER BasePath
    Base directory for Redis installation
    #>
    
    [CmdletBinding()]
    param(
        [string]$BasePath = (Get-Location).Path
    )
    
    Write-Host ""
    Write-Host "Redis for Windows Information" -ForegroundColor Cyan
    Write-Host "============================" -ForegroundColor Cyan
    Write-Host ""
    
    # Find and display executables
    $executables = Find-RedisExecutables -BasePath $BasePath
    
    Write-Host "Executable Locations:" -ForegroundColor Yellow
    Write-Host "  Redis Server: $(if($executables.RedisServer){$executables.RedisServer}else{'Not found'})" -ForegroundColor $(if ($executables.RedisServer) { 'Green' }else { 'Red' })
    Write-Host "  Redis CLI:    $(if($executables.RedisCli){$executables.RedisCli}else{'Not found'})" -ForegroundColor $(if ($executables.RedisCli) { 'Green' }else { 'Red' })
    Write-Host "  Redis Service:$(if($executables.RedisService){$executables.RedisService}else{'Not found'})" -ForegroundColor $(if ($executables.RedisService) { 'Green' }else { 'Red' })
    Write-Host ""
    
    # Service status
    $serviceStatus = Get-RedisServiceStatus
    Write-Host "Service Information:" -ForegroundColor Yellow
    Write-Host "  Service Exists:   $(if($serviceStatus.Exists){'Yes'}else{'No'})" -ForegroundColor $(if ($serviceStatus.Exists) { 'Green' }else { 'Red' })
    if ($serviceStatus.Exists) {
        Write-Host "  Status:           $($serviceStatus.Status)" -ForegroundColor $(if ($serviceStatus.Status -eq 'Running') { 'Green' }else { 'Yellow' })
        Write-Host "  Start Type:       $($serviceStatus.StartType)" -ForegroundColor Green
        if ($serviceStatus.ProcessId) {
            Write-Host "  Process ID:       $($serviceStatus.ProcessId)" -ForegroundColor Green
        }
    }
    Write-Host ""
    
    # Configuration files
    Write-Host "Configuration Files:" -ForegroundColor Yellow
    $redisConf = Join-Path $BasePath "redis.conf"
    $agentConf = Join-Path $BasePath "redis-agent.conf"
    Write-Host "  redis.conf:       $(if(Test-Path $redisConf){'✓ Found'}else{'✗ Not found'})" -ForegroundColor $(if (Test-Path $redisConf) { 'Green' }else { 'Red' })
    Write-Host "  redis-agent.conf: $(if(Test-Path $agentConf){'✓ Found'}else{'✗ Not found'})" -ForegroundColor $(if (Test-Path $agentConf) { 'Green' }else { 'Red' })
    Write-Host ""
    
    # Test connection if service is running
    if ($serviceStatus.Status -eq "Running") {
        Write-Host "Connection Test:" -ForegroundColor Yellow
        $connectionTest = Test-RedisConnection
        Write-Host "  Redis Response:   $(if($connectionTest){'✓ PONG'}else{'✗ No response'})" -ForegroundColor $(if ($connectionTest) { 'Green' }else { 'Red' })
        Write-Host ""
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Find-RedisExecutables',
    'Test-RedisSetup',
    'Start-RedisServer',
    'Stop-RedisServer',
    'Test-RedisConnection',
    'Install-RedisService',
    'Uninstall-RedisService',
    'Get-RedisServiceStatus',
    'Show-RedisInfo'
) -Variable @(
    'ModuleInfo'
) -Alias @()
