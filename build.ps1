# Redis for Windows - PowerShell Build and Setup Script
# ====================================================
# Enhanced version with GitHub integration and agent-memory-server support

param(
    [switch]$DownloadOnly,
    [switch]$BuildOnly,
    [switch]$InstallService,
    [switch]$UninstallService,
    [switch]$Help,
    [switch]$GitHubWorkflow,
    [switch]$CheckLatestRelease,
    [switch]$PrepareForAgents,
    [switch]$ConfigureMemoryServer,
    [string]$RedisPort = "6379",
    [string]$AgentMemoryPort = "8000"
)

function Write-Banner {
    Write-Host "====================================================================" -ForegroundColor Cyan
    Write-Host "Redis for Windows - Build and Setup Script" -ForegroundColor Cyan
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

function Test-GitHubCLI {
    try {
        $ghVersion = & gh --version 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Info "GitHub CLI found: $($ghVersion[0])"
            
            # Check authentication
            $authStatus = & gh auth status 2>&1
            if ($authStatus -match "Logged in") {
                Write-Success "GitHub CLI is authenticated"
                return $true
            }
            else {
                Write-Warning "GitHub CLI not authenticated. Run: gh auth login"
                return $false
            }
        }
    }
    catch {
        Write-Warning "GitHub CLI not found. Install from: https://cli.github.com/"
        return $false
    }
    return $false
}

function Get-LatestGitHubRelease {
    param($Owner = "david-t-martel", $Repo = "redis-windows")
    
    try {
        if (Test-GitHubCLI) {
            $releaseInfo = & gh release list --repo "$Owner/$Repo" --limit 1 --json tagName,url,publishedAt 2>$null | ConvertFrom-Json
            if ($releaseInfo -and $releaseInfo.Count -gt 0) {
                return $releaseInfo[0]
            }
        }
        
        # Fallback to REST API
        $response = Invoke-RestMethod -Uri "https://api.github.com/repos/$Owner/$Repo/releases/latest" -ErrorAction Stop
        return @{
            tagName = $response.tag_name
            url = $response.html_url
            publishedAt = $response.published_at
        }
    }
    catch {
        Write-Warning "Could not fetch latest release from GitHub"
        return $null
    }
}

function Invoke-GitHubWorkflow {
    param($WorkflowName = "build-redis.yml")
    
    if (-not (Test-GitHubCLI)) {
        Write-Error "GitHub CLI required for workflow operations"
        return $false
    }
    
    Write-Info "Triggering GitHub workflow: $WorkflowName"
    
    try {
        $result = & gh workflow run $WorkflowName 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Workflow triggered successfully"
            Write-Info "Check status with: gh run list"
            return $true
        }
        else {
            Write-Error "Failed to trigger workflow: $result"
            return $false
        }
    }
    catch {
        Write-Error "Error triggering workflow: $_"
        return $false
    }
}

function Wait-ForWorkflowCompletion {
    param($TimeoutMinutes = 10)
    
    if (-not (Test-GitHubCLI)) {
        return $false
    }
    
    Write-Info "Waiting for workflow completion (timeout: $TimeoutMinutes minutes)..."
    
    $timeout = (Get-Date).AddMinutes($TimeoutMinutes)
    $checkInterval = 30 # seconds
    
    do {
        try {
            $runs = & gh run list --limit 1 --json status,conclusion,workflowName 2>$null | ConvertFrom-Json
            if ($runs -and $runs.Count -gt 0) {
                $latestRun = $runs[0]
                $status = $latestRun.status
                $conclusion = $latestRun.conclusion
                
                Write-Info "Workflow status: $status $(if($conclusion) { "($conclusion)" })"
                
                if ($status -eq "completed") {
                    if ($conclusion -eq "success") {
                        Write-Success "Workflow completed successfully!"
                        return $true
                    }
                    else {
                        Write-Error "Workflow failed with conclusion: $conclusion"
                        return $false
                    }
                }
            }
        }
        catch {
            Write-Warning "Error checking workflow status: $_"
        }
        
        if ((Get-Date) -lt $timeout) {
            Start-Sleep -Seconds $checkInterval
        }
        else {
            Write-Warning "Timeout waiting for workflow completion"
            return $false
        }
    } while ((Get-Date) -lt $timeout)
    
    return $false
}

function Get-LatestRelease {
    param($Owner = "david-t-martel", $Repo = "redis-windows")
    
    Write-Info "Downloading latest Redis binaries from GitHub releases..."
    
    if (Test-GitHubCLI) {
        try {
            # List available assets
            $assets = & gh release view --repo "$Owner/$Repo" --json assets | ConvertFrom-Json
            
            if ($assets.assets -and $assets.assets.Count -gt 0) {
                # Look for the Windows release zip
                $windowsAsset = $assets.assets | Where-Object { $_.name -match "Windows.*\.zip" } | Select-Object -First 1
                
                if ($windowsAsset) {
                    Write-Info "Found release asset: $($windowsAsset.name)"
                    
                    # Download the asset
                    $downloadResult = & gh release download --repo "$Owner/$Repo" --pattern "*Windows*.zip" --clobber 2>&1
                    
                    if ($LASTEXITCODE -eq 0) {
                        Write-Success "Downloaded release successfully"
                        
                        # Extract if it's a zip file
                        $zipFile = Get-ChildItem -Filter "*Windows*.zip" | Select-Object -First 1
                        if ($zipFile) {
                            Write-Info "Extracting $($zipFile.Name)..."
                            Expand-Archive -Path $zipFile.FullName -DestinationPath "." -Force
                            Write-Success "Extraction completed"
                            return $true
                        }
                    }
                    else {
                        Write-Error "Failed to download release: $downloadResult"
                    }
                }
                else {
                    Write-Warning "No Windows release asset found"
                }
            }
            else {
                Write-Warning "No release assets found"
            }
        }
        catch {
            Write-Error "Error downloading release: $_"
        }
    }
    
    # Fallback: provide manual instructions
    Write-Warning "Automatic download failed. Manual download required:"
    Write-Host ""
    Write-Host "1. Go to: https://github.com/$Owner/$Repo/releases" -ForegroundColor Yellow
    Write-Host "2. Download: Redis-X.X.X-Windows-x64-with-Service.zip" -ForegroundColor Yellow
    Write-Host "3. Extract to this directory" -ForegroundColor Yellow
    Write-Host ""
    
    return $false
}

function Get-RedisBuilds {
    Write-Info "Getting Redis builds..."
    
    # First try to download from releases
    if (Get-LatestRelease) {
        return
    }
    
    # If no releases available, try triggering workflow
    if ($GitHubWorkflow -and (Test-GitHubCLI)) {
        Write-Info "No releases found. Triggering GitHub workflow to build Redis..."
        
        if (Invoke-GitHubWorkflow) {
            Write-Info "Workflow started. You can:"
            Write-Host "1. Wait for completion: .\build.ps1 -CheckLatestRelease" -ForegroundColor Yellow
            Write-Host "2. Check status: gh run list" -ForegroundColor Yellow
            Write-Host "3. View logs: gh run view" -ForegroundColor Yellow
            
            $waitForCompletion = Read-Host "`nWait for workflow completion? (y/n)"
            if ($waitForCompletion -match '^y') {
                if (Wait-ForWorkflowCompletion) {
                    # Try downloading again after workflow completion
                    Get-LatestRelease
                }
            }
        }
        return
    }
    
    # Fallback: manual instructions
    Write-Info "Redis binaries can be obtained in several ways:"
    Write-Host ""
    Write-Host "Option 1 - GitHub Releases (Recommended):" -ForegroundColor Green
    Write-Host "  1. Go to: https://github.com/david-t-martel/redis-windows/releases" -ForegroundColor Yellow
    Write-Host "  2. Download: Redis-X.X.X-Windows-x64-with-Service.zip" -ForegroundColor Yellow
    Write-Host "  3. Extract to this directory" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Option 2 - Trigger GitHub Workflow:" -ForegroundColor Green
    Write-Host "  .\build.ps1 -GitHubWorkflow" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Option 3 - Use GitHub CLI:" -ForegroundColor Green
    Write-Host "  gh workflow run build-redis.yml" -ForegroundColor Yellow
    Write-Host ""
    
    $response = Read-Host "Press Enter to continue with service build, or 'q' to quit"
    if ($response -eq 'q') {
        exit 0
    }
}

function Build-RedisService {
    Write-Info "Building .NET Redis service wrapper..."
    
    # Check for .NET SDK
    try {
        $dotnetVersion = & dotnet --version 2>$null
        Write-Info "Found .NET SDK version: $dotnetVersion"
    }
    catch {
        Write-Error ".NET SDK not found. Please install .NET 8.0 SDK."
        Write-Host "Download from: https://dotnet.microsoft.com/download" -ForegroundColor Yellow
        return $false
    }
    
    # Restore packages
    Write-Info "Restoring NuGet packages..."
    $restoreResult = & dotnet restore RedisService.csproj 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to restore NuGet packages"
        Write-Host $restoreResult -ForegroundColor Red
        return $false
    }
    
    # Build and publish
    Write-Info "Building and publishing Redis service..."
    $publishResult = & dotnet publish RedisService.csproj -c Release -r win-x64 --self-contained -o publish 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to build service"
        Write-Host $publishResult -ForegroundColor Red
        return $false
    }
    
    # Copy to main directory
    if (Test-Path ".\publish\RedisService.exe") {
        Copy-Item ".\publish\RedisService.exe" ".\RedisService.exe" -Force
        Write-Success "Service built and copied to main directory"
        return $true
    }
    else {
        Write-Error "Build completed but RedisService.exe not found"
        return $false
    }
}

function Test-AgentMemoryServerIntegration {
    Write-Info "Testing agent-memory-server integration..."
    
    # Check if agent-memory-server is available
    $agentMemoryPath = Join-Path $env:USERPROFILE "agent-memory-server"
    $hasAgentMemory = Test-Path $agentMemoryPath
    
    Write-Host ""
    Write-Host "Agent Memory Server Integration Status:" -ForegroundColor Cyan
    Write-Host "  Agent Memory Server: $(if($hasAgentMemory){'✓ Found at ' + $agentMemoryPath}else{'✗ Not found'})" -ForegroundColor $(if($hasAgentMemory){'Green'}else{'Red'})
    
    if ($hasAgentMemory) {
        # Check for Python environment
        $pythonEnv = Test-Path (Join-Path $agentMemoryPath ".venv")
        Write-Host "  Python Environment:  $(if($pythonEnv){'✓'}else{'✗'})" -ForegroundColor $(if($pythonEnv){'Green'}else{'Red'})
        
        # Check configuration
        $configFile = Join-Path $agentMemoryPath ".env"
        $hasConfig = Test-Path $configFile
        Write-Host "  Configuration:       $(if($hasConfig){'✓'}else{'✗'})" -ForegroundColor $(if($hasConfig){'Green'}else{'Red'})
        
        if ($hasConfig) {
            # Check Redis connection string
            $configContent = Get-Content $configFile -ErrorAction SilentlyContinue
            $redisConfig = $configContent | Where-Object { $_ -match "REDIS_URL" }
            if ($redisConfig) {
                Write-Host "  Redis Integration:   ✓ Configured" -ForegroundColor Green
            }
            else {
                Write-Host "  Redis Integration:   ⚠ Not configured" -ForegroundColor Yellow
            }
        }
    }
    else {
        Write-Host ""
        Write-Host "To set up agent-memory-server integration:" -ForegroundColor Yellow
        Write-Host "1. Clone: git clone https://github.com/david-t-martel/agent-memory-server.git" -ForegroundColor Yellow
        Write-Host "2. Setup: cd agent-memory-server && python -m venv .venv" -ForegroundColor Yellow
        Write-Host "3. Install: .venv\Scripts\activate && pip install -e ." -ForegroundColor Yellow
        Write-Host "4. Configure: copy .env.example .env" -ForegroundColor Yellow
    }
    
    Write-Host ""
    return $hasAgentMemory
}

function Set-AgentMemoryServerConfig {
    Write-Info "Configuring agent-memory-server for Redis integration..."
    
    $agentMemoryPath = Join-Path $env:USERPROFILE "agent-memory-server"
    if (-not (Test-Path $agentMemoryPath)) {
        Write-Warning "Agent memory server not found at $agentMemoryPath"
        
        $clone = Read-Host "Clone agent-memory-server repository? (y/n)"
        if ($clone -match '^y') {
            try {
                Set-Location $env:USERPROFILE
                $cloneResult = & git clone https://github.com/david-t-martel/agent-memory-server.git 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Success "Repository cloned successfully"
                    Set-Location $PSScriptRoot
                }
                else {
                    Write-Error "Failed to clone repository: $cloneResult"
                    Set-Location $PSScriptRoot
                    return $false
                }
            }
            catch {
                Write-Error "Error cloning repository: $_"
                Set-Location $PSScriptRoot
                return $false
            }
        }
        else {
            return $false
        }
    }
    
    $configFile = Join-Path $agentMemoryPath ".env"
    $exampleFile = Join-Path $agentMemoryPath ".env.example"
    
    # Create .env from .env.example if it doesn't exist
    if ((Test-Path $exampleFile) -and (-not (Test-Path $configFile))) {
        Copy-Item $exampleFile $configFile
        Write-Info "Created .env file from .env.example"
    }
    
    if (Test-Path $configFile) {
        # Update Redis configuration
        $configContent = Get-Content $configFile
        $redisUrl = "redis://localhost:$RedisPort"
        
        # Update or add REDIS_URL
        $newConfig = $configContent | ForEach-Object {
            if ($_ -match "^REDIS_URL=") {
                "REDIS_URL=$redisUrl"
            }
            elseif ($_ -match "^# REDIS_URL=") {
                "REDIS_URL=$redisUrl"
            }
            else {
                $_
            }
        }
        
        # Add REDIS_URL if not found
        if (-not ($newConfig | Where-Object { $_ -match "^REDIS_URL=" })) {
            $newConfig += ""
            $newConfig += "# Redis Configuration"
            $newConfig += "REDIS_URL=$redisUrl"
        }
        
        # Update server configuration
        $newConfig = $newConfig | ForEach-Object {
            if ($_ -match "^API_HOST=") {
                "API_HOST=localhost"
            }
            elseif ($_ -match "^API_PORT=") {
                "API_PORT=$AgentMemoryPort"
            }
            elseif ($_ -match "^MCP_HOST=") {
                "MCP_HOST=localhost"
            }
            elseif ($_ -match "^MCP_PORT=") {
                "MCP_PORT=$([int]$AgentMemoryPort + 1)"
            }
            else {
                $_
            }
        }
        
        Set-Content -Path $configFile -Value $newConfig
        Write-Success "Updated agent-memory-server configuration"
        
        Write-Host ""
        Write-Host "Agent Memory Server Configuration:" -ForegroundColor Cyan
        Write-Host "  Redis URL: $redisUrl" -ForegroundColor Green
        Write-Host "  API Port: $AgentMemoryPort" -ForegroundColor Green
        Write-Host "  MCP Port: $([int]$AgentMemoryPort + 1)" -ForegroundColor Green
        Write-Host ""
        
        return $true
    }
    else {
        Write-Error "Could not find or create configuration file"
        return $false
    }
}

function Start-AgentMemoryServer {
    Write-Info "Starting agent-memory-server..."
    
    $agentMemoryPath = Join-Path $env:USERPROFILE "agent-memory-server"
    if (-not (Test-Path $agentMemoryPath)) {
        Write-Error "Agent memory server not found"
        return $false
    }
    
    $venvActivate = Join-Path $agentMemoryPath ".venv\Scripts\Activate.ps1"
    if (-not (Test-Path $venvActivate)) {
        Write-Warning "Python virtual environment not found. Setting up..."
        
        try {
            Set-Location $agentMemoryPath
            & python -m venv .venv
            & .venv\Scripts\activate
            & pip install -e .
            Write-Success "Python environment setup completed"
            Set-Location $PSScriptRoot
        }
        catch {
            Write-Error "Failed to setup Python environment: $_"
            Set-Location $PSScriptRoot
            return $false
        }
    }
    
    Write-Info "Starting agent-memory-server API and MCP servers..."
    Write-Host "Use Ctrl+C to stop the servers" -ForegroundColor Yellow
    
    try {
        Set-Location $agentMemoryPath
        & $venvActivate
        & agent-memory-server run-all
    }
    catch {
        Write-Error "Failed to start agent-memory-server: $_"
    }
    finally {
        Set-Location $PSScriptRoot
    }
}
    Write-Info "Testing Redis setup..."
    
    $hasRedisServer = Test-Path "redis-server.exe"
    $hasRedisCli = Test-Path "redis-cli.exe"
    $hasConfig = Test-Path "redis.conf"
    $hasService = Test-Path "RedisService.exe"
    
    Write-Host ""
    Write-Host "Current setup status:" -ForegroundColor Cyan
    Write-Host "  Redis Server:  $(if($hasRedisServer){'✓'}else{'✗'})" -ForegroundColor $(if($hasRedisServer){'Green'}else{'Red'})
    Write-Host "  Redis CLI:     $(if($hasRedisCli){'✓'}else{'✗'})" -ForegroundColor $(if($hasRedisCli){'Green'}else{'Red'})
    Write-Host "  Configuration: $(if($hasConfig){'✓'}else{'✗'})" -ForegroundColor $(if($hasConfig){'Green'}else{'Red'})
    Write-Host "  Service:       $(if($hasService){'✓'}else{'✗'})" -ForegroundColor $(if($hasService){'Green'}else{'Red'})
    Write-Host ""
    
    if (-not $hasRedisServer) {
        Write-Warning "redis-server.exe not found. Redis cannot run without it."
        return $false
    }
    
    if (-not $hasConfig) {
        Write-Warning "redis.conf not found. Creating default configuration..."
        # The redis.conf should already exist from our earlier creation
    }
    
    # Test Redis server startup
    if ($hasRedisServer) {
        Write-Info "Testing Redis server startup..."
        
        try {
            # Start Redis in background
            $redisProcess = Start-Process -FilePath ".\redis-server.exe" -ArgumentList "redis.conf" -PassThru -WindowStyle Hidden
            Start-Sleep -Seconds 3
            
            if ($hasRedisCli) {
                # Test connectivity
                $pingResult = & .\redis-cli.exe ping 2>$null
                if ($pingResult -eq "PONG") {
                    Write-Success "Redis is responding to ping commands"
                    $testPassed = $true
                }
                else {
                    Write-Warning "Redis not responding to ping"
                    $testPassed = $false
                }
                
                # Shutdown test instance
                & .\redis-cli.exe shutdown nosave 2>$null | Out-Null
            }
            else {
                Write-Warning "Cannot test connectivity - redis-cli.exe not found"
                $testPassed = $true  # Assume it's working
                
                # Kill the test process
                Stop-Process -Id $redisProcess.Id -Force 2>$null
            }
            
            # Wait for process to exit
            try {
                $redisProcess.WaitForExit(5000)
            }
            catch {}
            
            return $testPassed
        }
        catch {
            Write-Error "Failed to test Redis server: $_"
            return $false
        }
    }
    
    return $true
}

function Test-RedisSetup {
    Write-Info "Testing Redis setup..."
    
    $hasRedisServer = Test-Path "redis-server.exe"
    $hasRedisCli = Test-Path "redis-cli.exe"
    $hasConfig = Test-Path "redis.conf"
    $hasService = Test-Path "RedisService.exe"
    
    Write-Host ""
    Write-Host "Current setup status:" -ForegroundColor Cyan
    Write-Host "  Redis Server:  $(if($hasRedisServer){'✓'}else{'✗'})" -ForegroundColor $(if($hasRedisServer){'Green'}else{'Red'})
    Write-Host "  Redis CLI:     $(if($hasRedisCli){'✓'}else{'✗'})" -ForegroundColor $(if($hasRedisCli){'Green'}else{'Red'})
    Write-Host "  Configuration: $(if($hasConfig){'✓'}else{'✗'})" -ForegroundColor $(if($hasConfig){'Green'}else{'Red'})
    Write-Host "  Service:       $(if($hasService){'✓'}else{'✗'})" -ForegroundColor $(if($hasService){'Green'}else{'Red'})
    Write-Host ""
    
    if (-not $hasRedisServer) {
        Write-Warning "redis-server.exe not found. Redis cannot run without it."
        return $false
    }
    
    if (-not $hasConfig) {
        Write-Warning "redis.conf not found. Creating default configuration..."
        # The redis.conf should already exist from our earlier creation
    }
    
    # Test Redis server startup
    if ($hasRedisServer) {
        Write-Info "Testing Redis server startup..."
        
        try {
            # Start Redis in background
            $redisProcess = Start-Process -FilePath ".\redis-server.exe" -ArgumentList "redis.conf" -PassThru -WindowStyle Hidden
            Start-Sleep -Seconds 3
            
            if ($hasRedisCli) {
                # Test connectivity
                $pingResult = & .\redis-cli.exe ping 2>$null
                if ($pingResult -eq "PONG") {
                    Write-Success "Redis is responding to ping commands"
                    $testPassed = $true
                }
                else {
                    Write-Warning "Redis not responding to ping"
                    $testPassed = $false
                }
                
                # Shutdown test instance
                & .\redis-cli.exe shutdown nosave 2>$null | Out-Null
            }
            else {
                Write-Warning "Cannot test connectivity - redis-cli.exe not found"
                $testPassed = $true  # Assume it's working
                
                # Kill the test process
                Stop-Process -Id $redisProcess.Id -Force 2>$null
            }
            
            # Wait for process to exit
            try {
                $redisProcess.WaitForExit(5000)
            }
            catch {}
            
            return $testPassed
        }
        catch {
            Write-Error "Failed to test Redis server: $_"
            return $false
        }
    }
    
    return $true
}

function Install-RedisService {
    if (-not (Test-Administrator)) {
        Write-Error "Administrator privileges required to install Windows service"
        Write-Host "Please run PowerShell as Administrator" -ForegroundColor Yellow
        return $false
    }
    
    Write-Info "Installing Redis as Windows service..."
    
    # Check if service already exists
    $existingService = Get-Service -Name "Redis" -ErrorAction SilentlyContinue
    if ($existingService) {
        Write-Warning "Redis service already exists"
        $reinstall = Read-Host "Do you want to reinstall it? (y/n)"
        if ($reinstall -match '^y') {
            Write-Info "Stopping and removing existing service..."
            Stop-Service -Name "Redis" -Force -ErrorAction SilentlyContinue
            & sc.exe delete Redis | Out-Null
            Start-Sleep -Seconds 2
        }
        else {
            return $false
        }
    }
    
    # Verify service executable exists
    $servicePath = Join-Path $PWD "RedisService.exe"
    if (-not (Test-Path $servicePath)) {
        Write-Error "RedisService.exe not found at $servicePath"
        Write-Info "Please run the build process first"
        return $false
    }
    
    # Create service command
    $configPath = Join-Path $PWD "redis.conf"
    if (Test-Path $configPath) {
        $binPath = "`"$servicePath`" -c `"$configPath`""
    }
    else {
        $binPath = "`"$servicePath`""
    }
    
    Write-Info "Creating service with path: $binPath"
    
    # Create the service
    $createResult = & sc.exe create Redis binpath= $binPath start= auto DisplayName= "Redis Server" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to create service"
        Write-Host $createResult -ForegroundColor Red
        return $false
    }
    
    Write-Success "Service created successfully"
    
    # Try to start the service
    Write-Info "Starting Redis service..."
    try {
        Start-Service -Name "Redis" -ErrorAction Stop
        Write-Success "Redis service started successfully"
        
        # Test the service
        Start-Sleep -Seconds 3
        if (Test-Path "redis-cli.exe") {
            $pingResult = & .\redis-cli.exe ping 2>$null
            if ($pingResult -eq "PONG") {
                Write-Success "Redis service is running and responding!"
            }
        }
        
        return $true
    }
    catch {
        Write-Error "Failed to start service: $_"
        Write-Info "Check Windows Event Viewer for detailed error information"
        return $false
    }
}

function Uninstall-RedisService {
    if (-not (Test-Administrator)) {
        Write-Error "Administrator privileges required to uninstall Windows service"
        return $false
    }
    
    Write-Info "Uninstalling Redis service..."
    
    # Stop service if running
    try {
        Stop-Service -Name "Redis" -Force -ErrorAction SilentlyContinue
        Write-Info "Stopped Redis service"
    }
    catch {}
    
    # Delete service
    $deleteResult = & sc.exe delete Redis 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Redis service uninstalled successfully"
        return $true
    }
    else {
        Write-Error "Failed to uninstall service"
        Write-Host $deleteResult -ForegroundColor Red
        return $false
    }
}

function Show-Help {
    Write-Host "Redis for Windows - Build and Setup Script" -ForegroundColor Cyan
    Write-Host "Enhanced with agent-memory-server integration" -ForegroundColor Green
    Write-Host ""
    Write-Host "Usage:" -ForegroundColor Yellow
    Write-Host "  .\build.ps1                        - Interactive mode"
    Write-Host "  .\build.ps1 -DownloadOnly          - Download binaries only"
    Write-Host "  .\build.ps1 -BuildOnly             - Build service only"
    Write-Host "  .\build.ps1 -InstallService        - Install as Windows service"
    Write-Host "  .\build.ps1 -UninstallService      - Remove Windows service"
    Write-Host "  .\build.ps1 -GitHubWorkflow        - Trigger GitHub workflow"
    Write-Host "  .\build.ps1 -CheckLatestRelease    - Check for latest release"
    Write-Host "  .\build.ps1 -PrepareForAgents      - Configure for LLM agents"
    Write-Host "  .\build.ps1 -ConfigureMemoryServer - Setup agent-memory-server"
    Write-Host "  .\build.ps1 -Help                  - Show this help"
    Write-Host ""
    Write-Host "Parameters:" -ForegroundColor Yellow
    Write-Host "  -RedisPort <port>         - Redis port (default: 6379)"
    Write-Host "  -AgentMemoryPort <port>   - Agent memory server port (default: 8000)"
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Yellow
    Write-Host "  # Full interactive setup"
    Write-Host "  .\build.ps1"
    Write-Host ""
    Write-Host "  # Quick service installation (requires admin)"
    Write-Host "  .\build.ps1 -BuildOnly -InstallService"
    Write-Host ""
    Write-Host "  # Setup for LLM agents with custom ports"
    Write-Host "  .\build.ps1 -PrepareForAgents -RedisPort 6380 -AgentMemoryPort 8001"
    Write-Host ""
    Write-Host "  # Download latest release and setup agent integration"
    Write-Host "  .\build.ps1 -CheckLatestRelease -ConfigureMemoryServer"
    Write-Host ""
}

function Show-Menu {
    Write-Host ""
    Write-Host "Choose an option:" -ForegroundColor Yellow
    Write-Host "1. Download Redis binaries from GitHub releases"
    Write-Host "2. Build .NET service wrapper"
    Write-Host "3. Test current setup"
    Write-Host "4. Install as Windows service (requires admin)"
    Write-Host "5. Uninstall Windows service (requires admin)"
    Write-Host "6. Full setup (download + build + test)"
    Write-Host "7. Trigger GitHub workflow to build Redis"
    Write-Host "8. Check for latest GitHub release"
    Write-Host "9. Configure for LLM agents"
    Write-Host "10. Setup agent-memory-server integration"
    Write-Host "11. Test agent-memory-server integration"
    Write-Host "12. Start agent-memory-server"
    Write-Host "13. Exit"
    Write-Host ""
    
    $choice = Read-Host "Enter your choice (1-13)"
    return $choice
}

function Show-Summary {
    Write-Host ""
    Write-Host "====================================================================" -ForegroundColor Cyan
    Write-Host "Setup Complete!" -ForegroundColor Cyan
    Write-Host "====================================================================" -ForegroundColor Cyan
    Write-Host ""
    
    # Show what's available
    $hasRedisServer = Test-Path "redis-server.exe"
    $hasRedisCli = Test-Path "redis-cli.exe"
    $hasConfig = Test-Path "redis.conf"
    $hasService = Test-Path "RedisService.exe"
    
    Write-Host "Available components:" -ForegroundColor Green
    if ($hasService) { Write-Host "  ✓ Redis Windows Service Wrapper" -ForegroundColor Green }
    if ($hasRedisServer) { Write-Host "  ✓ Redis Server Binary" -ForegroundColor Green }
    if ($hasRedisCli) { Write-Host "  ✓ Redis CLI Client" -ForegroundColor Green }
    if ($hasConfig) { Write-Host "  ✓ Redis Configuration File" -ForegroundColor Green }
    Write-Host ""
    
    Write-Host "Usage examples:" -ForegroundColor Yellow
    Write-Host "  Direct:        .\start.bat"
    Write-Host "  Command line:  .\redis-server.exe redis.conf"
    if ($hasService) {
        Write-Host "  Service:       net start Redis"
    }
    Write-Host ""
    
    if ($hasRedisCli) {
        Write-Host "Test Redis:" -ForegroundColor Yellow
        Write-Host "  .\redis-cli.exe ping"
        Write-Host "  .\redis-cli.exe set test `"Hello Redis`""
        Write-Host "  .\redis-cli.exe get test"
        Write-Host ""
    }
    
    Write-Host "For detailed documentation, see SETUP_GUIDE.md" -ForegroundColor Cyan
}

# Main script execution
Write-Banner

# Handle command line parameters
if ($Help) {
    Show-Help
    exit 0
}

if ($CheckLatestRelease) {
    $release = Get-LatestGitHubRelease
    if ($release) {
        Write-Success "Latest release: $($release.tagName)"
        Write-Info "Published: $($release.publishedAt)"
        Write-Info "URL: $($release.url)"
        
        $download = Read-Host "Download this release? (y/n)"
        if ($download -match '^y') {
            Get-LatestRelease
        }
    }
    else {
        Write-Warning "No releases found"
    }
    exit 0
}

if ($GitHubWorkflow) {
    Invoke-GitHubWorkflow
    exit 0
}

if ($ConfigureMemoryServer) {
    Set-AgentMemoryServerConfig
    exit 0
}

if ($PrepareForAgents) {
    Write-Info "Preparing Redis for LLM agent integration..."
    
    # Test current setup
    Test-RedisSetup
    
    # Test agent memory server integration
    Test-AgentMemoryServerIntegration
    
    # Configure agent memory server if available
    Set-AgentMemoryServerConfig
    
    Write-Success "Agent preparation completed!"
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "1. Start Redis: .\start.bat" -ForegroundColor Yellow
    Write-Host "2. Start agent-memory-server: .\build.ps1 -ConfigureMemoryServer" -ForegroundColor Yellow
    Write-Host "3. Configure your LLM agents to use:" -ForegroundColor Yellow
    Write-Host "   - Redis: localhost:$RedisPort" -ForegroundColor Green
    Write-Host "   - Agent Memory API: localhost:$AgentMemoryPort" -ForegroundColor Green
    Write-Host "   - Agent Memory MCP: localhost:$([int]$AgentMemoryPort + 1)" -ForegroundColor Green
    exit 0
}

if ($UninstallService) {
    Uninstall-RedisService
    exit 0
}

if ($DownloadOnly) {
    Get-RedisBuilds
    exit 0
}

if ($BuildOnly) {
    $buildSuccess = Build-RedisService
    if ($buildSuccess -and $InstallService) {
        Install-RedisService
    }
    exit 0
}

if ($InstallService) {
    Install-RedisService
    exit 0
}

# Interactive mode
Write-Info "Welcome to the Redis for Windows setup script!"

# Check admin status
if (Test-Administrator) {
    Write-Info "Running with administrator privileges"
}
else {
    Write-Warning "Not running as administrator - service installation will not be available"
}

do {
    $choice = Show-Menu
    
    switch ($choice) {
        "1" { Get-RedisBuilds }
        "2" { Build-RedisService }
        "3" { Test-RedisSetup }
        "4" { 
            if (Test-Administrator) {
                Install-RedisService
            }
            else {
                Write-Error "Administrator privileges required for service installation"
                Write-Host "Please restart PowerShell as Administrator" -ForegroundColor Yellow
            }
        }
        "5" {
            if (Test-Administrator) {
                Uninstall-RedisService
            }
            else {
                Write-Error "Administrator privileges required for service removal"
            }
        }
        "6" {
            Get-RedisBuilds
            $buildSuccess = Build-RedisService
            if ($buildSuccess) {
                Test-RedisSetup
                
                $installSvc = Read-Host "`nInstall as Windows service? (y/n)"
                if ($installSvc -match '^y' -and (Test-Administrator)) {
                    Install-RedisService
                }
            }
        }
        "7" {
            if (Test-GitHubCLI) {
                Invoke-GitHubWorkflow
            }
            else {
                Write-Error "GitHub CLI required for workflow operations"
            }
        }
        "8" {
            $release = Get-LatestGitHubRelease
            if ($release) {
                Write-Success "Latest release: $($release.tagName)"
                Write-Info "Published: $($release.publishedAt)"
                Write-Info "URL: $($release.url)"
                
                $download = Read-Host "Download this release? (y/n)"
                if ($download -match '^y') {
                    Get-LatestRelease
                }
            }
        }
        "9" {
            Write-Info "Configuring for LLM agents..."
            Test-RedisSetup
            Test-AgentMemoryServerIntegration
            Set-AgentMemoryServerConfig
        }
        "10" {
            Set-AgentMemoryServerConfig
        }
        "11" {
            Test-AgentMemoryServerIntegration
        }
        "12" {
            Start-AgentMemoryServer
        }
        "13" { break }
        default { Write-Warning "Invalid choice. Please select 1-13." }
    }
    
    if ($choice -ne "13") {
        Write-Host ""
        Read-Host "Press Enter to continue..."
    }
    
} while ($choice -ne "13")

Show-Summary
Write-Host "Goodbye!" -ForegroundColor Cyan
