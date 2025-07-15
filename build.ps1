# Redis for Windows - PowerShell Build and Setup Script
# ====================================================
# Enhanced version with GitHub integration and agent-memory-server support
# Modular architecture with utilities

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
    [switch]$SetupUvEnvironment,
    [switch]$TestRedis,
    [switch]$ShowRedisInfo,
    [switch]$StartRedis,
    [switch]$StopRedis,
    [string]$RedisPort = "6379",
    [string]$AgentMemoryPort = "8000"
)

# Import utility modules
$script:ModulesPath = Join-Path $PSScriptRoot "utilities"

# Import UV Environment module
$uvModulePath = Join-Path $script:ModulesPath "UVEnvironment.psm1"
if (Test-Path $uvModulePath) {
    Import-Module $uvModulePath -Force -Global
    Write-Host "[MODULE] UVEnvironment module loaded" -ForegroundColor Green
}
else {
    Write-Host "[WARNING] UVEnvironment module not found at: $uvModulePath" -ForegroundColor Yellow
}

# Import Redis Utilities module
$redisModulePath = Join-Path $script:ModulesPath "RedisUtilities.psm1"
if (Test-Path $redisModulePath) {
    Import-Module $redisModulePath -Force -Global
    Write-Host "[MODULE] RedisUtilities module loaded" -ForegroundColor Green
}
else {
    Write-Host "[WARNING] RedisUtilities module not found at: $redisModulePath" -ForegroundColor Yellow
}

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
            $releaseInfo = & gh release list --repo "$Owner/$Repo" --limit 1 --json tagName, url, publishedAt 2>$null | ConvertFrom-Json
            if ($releaseInfo -and $releaseInfo.Count -gt 0) {
                return $releaseInfo[0]
            }
        }
        
        # Fallback to REST API
        $response = Invoke-RestMethod -Uri "https://api.github.com/repos/$Owner/$Repo/releases/latest" -ErrorAction Stop
        return @{
            tagName     = $response.tag_name
            url         = $response.html_url
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
            $runs = & gh run list --limit 1 --json status, conclusion, workflowName 2>$null | ConvertFrom-Json
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

function Test-UvInstallation {
    try {
        $uvVersion = & uv --version 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Info "UV found: $uvVersion"
            
            # Check UV-managed Python
            $uvPython = & uv python list 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Info "UV-managed Python versions available"
                return $true
            }
            else {
                Write-Warning "UV found but no Python installations detected"
                Write-Info "Installing Python via UV..."
                & uv python install 3.13
                return $true
            }
        }
    }
    catch {
        Write-Warning "UV not found. Install from: https://docs.astral.sh/uv/getting-started/installation/"
        return $false
    }
    return $false
}

function Test-AgentMemoryServerIntegration {
    Write-Info "Testing agent-memory-server integration with centralized UV environment..."
    
    # Check if UV is available
    $hasUv = Test-UvInstallation
    Write-Host ""
    Write-Host "Agent Memory Server Integration Status:" -ForegroundColor Cyan
    Write-Host "  UV Package Manager:  $(if($hasUv){'✓'}else{'✗'})" -ForegroundColor $(if ($hasUv) { 'Green' }else { 'Red' })
    
    # Check centralized venv
    $centralVenv = "C:\users\david\.venv"
    $hasCentralVenv = Test-Path $centralVenv
    Write-Host "  Central Python Env:  $(if($hasCentralVenv){'✓ Found at ' + $centralVenv}else{'✗ Not found'})" -ForegroundColor $(if ($hasCentralVenv) { 'Green' }else { 'Red' })
    
    # Check if agent-memory-server is available
    $agentMemoryPath = Join-Path $env:USERPROFILE "agent-memory-server"
    $hasAgentMemory = Test-Path $agentMemoryPath
    Write-Host "  Agent Memory Server: $(if($hasAgentMemory){'✓ Found at ' + $agentMemoryPath}else{'✗ Not found'})" -ForegroundColor $(if ($hasAgentMemory) { 'Green' }else { 'Red' })
    
    if ($hasAgentMemory) {
        # Check configuration
        $configFile = Join-Path $agentMemoryPath ".env"
        $hasConfig = Test-Path $configFile
        Write-Host "  Configuration:       $(if($hasConfig){'✓'}else{'✗'})" -ForegroundColor $(if ($hasConfig) { 'Green' }else { 'Red' })
        
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
        
        # Check if agent-memory-server is installed in central venv
        if ($hasCentralVenv) {
            $agentMemoryBin = Join-Path $centralVenv "Scripts\agent-memory-server.exe"
            $hasAgentMemoryInstalled = Test-Path $agentMemoryBin
            Write-Host "  Agent Memory Install: $(if($hasAgentMemoryInstalled){'✓ Installed in central venv'}else{'✗ Not installed'})" -ForegroundColor $(if ($hasAgentMemoryInstalled) { 'Green' }else { 'Red' })
        }
    }
    else {
        Write-Host ""
        Write-Host "To set up agent-memory-server integration with UV:" -ForegroundColor Yellow
        Write-Host "1. Clone: git clone https://github.com/david-t-martel/agent-memory-server.git" -ForegroundColor Yellow
        Write-Host "2. Setup: Use this script's -ConfigureMemoryServer option" -ForegroundColor Yellow
        Write-Host "3. UV will manage the centralized environment automatically" -ForegroundColor Yellow
    }
    
    Write-Host ""
    return $hasAgentMemory -and $hasUv -and $hasCentralVenv
}

function Set-AgentMemoryServerConfig {
    Write-Info "Configuring agent-memory-server for Redis integration using UV..."
    
    # Check UV first
    if (-not (Test-UvInstallation)) {
        Write-Error "UV is required for centralized Python environment management"
        Write-Host "Install UV from: https://docs.astral.sh/uv/getting-started/installation/" -ForegroundColor Yellow
        return $false
    }
    
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
    
    # Install agent-memory-server in central venv using UV
    Write-Info "Installing agent-memory-server in centralized environment with UV..."
    try {
        Set-Location $agentMemoryPath
        
        # Ensure we have UV-managed Python 3.13
        Write-Info "Ensuring Python 3.13 is available via UV..."
        & uv python install 3.13 2>&1 | Out-Null
        
        # Create or use centralized venv with UV-managed Python
        $centralVenv = "C:\users\david\.venv"
        if (-not (Test-Path $centralVenv)) {
            Write-Info "Creating centralized virtual environment with UV-managed Python..."
            & uv venv $centralVenv --python 3.13 2>&1
        }
        
        # Install in centralized venv using UV
        Write-Info "Installing agent-memory-server with UV..."
        $installResult = & uv pip install --python $centralVenv -e . 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to install agent-memory-server: $installResult"
            Set-Location $PSScriptRoot
            return $false
        }
        
        Write-Success "Agent-memory-server installed successfully with UV"
        Set-Location $PSScriptRoot
    }
    catch {
        Write-Error "Error installing agent-memory-server: $_"
        Set-Location $PSScriptRoot
        return $false
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
    Write-Info "Starting agent-memory-server with centralized UV environment..."
    
    # Check UV first
    if (-not (Test-UvInstallation)) {
        Write-Error "UV is required for centralized Python environment management"
        return $false
    }
    
    $agentMemoryPath = Join-Path $env:USERPROFILE "agent-memory-server"
    if (-not (Test-Path $agentMemoryPath)) {
        Write-Error "Agent memory server not found"
        Write-Info "Run .\build.ps1 -ConfigureMemoryServer to set up agent-memory-server"
        return $false
    }
    
    # Check centralized venv
    $centralVenv = "C:\users\david\.venv"
    $agentMemoryBin = Join-Path $centralVenv "Scripts\agent-memory-server.exe"
    
    if (-not (Test-Path $agentMemoryBin)) {
        Write-Warning "Agent-memory-server not found in centralized environment. Installing..."
        
        try {
            Set-Location $agentMemoryPath
            
            # Create centralized venv if it doesn't exist using UV-managed Python
            if (-not (Test-Path $centralVenv)) {
                Write-Info "Creating centralized virtual environment with UV-managed Python..."
                & uv python install 3.13 2>&1 | Out-Null
                & uv venv $centralVenv --python 3.13
            }
            
            # Install agent-memory-server using UV
            Write-Info "Installing agent-memory-server with UV..."
            & uv pip install --python $centralVenv -e .
            
            if ($LASTEXITCODE -ne 0) {
                Write-Error "Failed to install agent-memory-server"
                Set-Location $PSScriptRoot
                return $false
            }
            
            Write-Success "Agent-memory-server installed successfully"
            Set-Location $PSScriptRoot
        }
        catch {
            Write-Error "Failed to setup agent-memory-server: $_"
            Set-Location $PSScriptRoot
            return $false
        }
    }
    
    Write-Info "Starting agent-memory-server API and MCP servers..."
    Write-Host "Use Ctrl+C to stop the servers" -ForegroundColor Yellow
    Write-Host "Using centralized UV environment: $centralVenv" -ForegroundColor Cyan
    
    try {
        # Use UV to run the command with the centralized venv
        Set-Location $agentMemoryPath
        
        # Set environment to use UV-managed Python explicitly
        $env:PATH = "$centralVenv\Scripts;$env:PATH"
        
        # Use UV run to execute with the correct Python environment
        & uv run --python $centralVenv agent-memory-server run-all
    }
    catch {
        Write-Error "Failed to start agent-memory-server: $_"
    }
    finally {
        Set-Location $PSScriptRoot
    }
}

function Setup-UvEnvironment {
    <#
    .SYNOPSIS
    Sets up UV environment using the UVEnvironment module
    
    .DESCRIPTION
    Wrapper function that uses the UVEnvironment PowerShell module for setting up
    centralized UV environment for LLM agents
    #>
    
    Write-Info "Setting up centralized UV environment for LLM agents..."
    
    # Check if UVEnvironment module is loaded
    if (-not (Get-Module -Name UVEnvironment)) {
        Write-Error "UVEnvironment module is not loaded"
        return $false
    }
    
    try {
        # Use the module function
        $result = Initialize-UVEnvironment
        
        if ($result) {
            Write-Success "UV environment setup completed using UVEnvironment module!"
            
            # Show environment information
            Show-UVEnvironmentInfo
            
            return $true
        }
        else {
            Write-Error "UV environment setup failed"
            return $false
        }
    }
    catch {
        Write-Error "Error setting up UV environment: $_"
        return $false
    }
}
& uv python install 3.13 2>&1 | Out-Null
        
# Create venv with UV-managed Python
$createResult = & uv venv $centralVenv --python 3.13 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create centralized venv: $createResult"
    return $false
}
Write-Success "Centralized virtual environment created with UV-managed Python 3.13"
}
else {
    Write-Info "Centralized virtual environment already exists at $centralVenv"
        
    # Verify it's using UV-managed Python
    $pythonPath = Join-Path $centralVenv "Scripts\python.exe"
    if (Test-Path $pythonPath) {
        $pythonVersion = & $pythonPath --version 2>&1
        Write-Info "Using Python: $pythonVersion"
    }
}
    
# Install common LLM agent dependencies using UV
Write-Info "Installing common LLM agent dependencies with UV..."
$packages = @(
    "redis",
    "fastapi",
    "uvicorn",
    "pydantic",
    "python-dotenv",
    "httpx",
    "aiofiles"
)
    
try {
    foreach ($package in $packages) {
        Write-Info "Installing $package with UV..."
        $installResult = & uv pip install --python $centralVenv $package 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Failed to install $package : $installResult"
        }
        else {
            Write-Success "Installed $package"
        }
    }
    Write-Success "Common dependencies installed via UV"
}
catch {
    Write-Error "Error installing dependencies: $_"
    return $false
}
    
# Configure agent-memory-server if available
$agentMemoryPath = Join-Path $env:USERPROFILE "agent-memory-server"
if (Test-Path $agentMemoryPath) {
    Write-Info "Installing agent-memory-server in centralized environment with UV..."
    try {
        Set-Location $agentMemoryPath
        $installResult = & uv pip install --python $centralVenv -e . 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Agent-memory-server installed in centralized environment"
        }
        else {
            Write-Warning "Failed to install agent-memory-server: $installResult"
        }
        Set-Location $PSScriptRoot
    }
    catch {
        Write-Error "Error installing agent-memory-server: $_"
        Set-Location $PSScriptRoot
    }
}
    
# Set up comprehensive UV environment aliases for this PowerShell session
Write-Info "Setting up UV environment aliases..."
    
# Set up Python alias
$uvPythonPath = Join-Path $centralVenv "Scripts\python.exe"
if (Test-Path $uvPythonPath) {
    # Create function aliases to ensure we use UV-managed Python
    $global:UvPython = $uvPythonPath
    Write-Success "UV Python alias configured: $global:UvPython"
        
    # Test the Python installation
    $testResult = & $global:UvPython --version 2>&1
    Write-Info "UV Python version: $testResult"
}
    
# Set up UV command aliases to ensure consistent UV usage
Write-Info "Setting up UV command aliases..."
    
# Check if UV is in PATH and get its location
try {
    $uvPath = (Get-Command uv -ErrorAction Stop).Source
    Write-Info "UV executable found at: $uvPath"
        
    # Create global aliases for UV commands
    $global:UV = $uvPath
        
    # UV subcommands (all available commands from help)
    $global:UVRun = "$uvPath run"
    $global:UVInit = "$uvPath init"
    $global:UVAdd = "$uvPath add"
    $global:UVRemove = "$uvPath remove"
    $global:UVVersion = "$uvPath version"
    $global:UVSync = "$uvPath sync"
    $global:UVLock = "$uvPath lock"
    $global:UVExport = "$uvPath export"
    $global:UVTree = "$uvPath tree"
    $global:UVTool = "$uvPath tool"
    $global:UVPythonCmd = "$uvPath python"
    $global:UVPip = "$uvPath pip"
    $global:UVVenv = "$uvPath venv"
    $global:UVBuild = "$uvPath build"
    $global:UVPublish = "$uvPath publish"
    $global:UVCache = "$uvPath cache"
    $global:UVSelf = "$uvPath self"
    $global:UVHelp = "$uvPath help"
        
    # Create PowerShell functions for easier usage with approved verbs
    function global:Invoke-UvRun { & $global:UV run @args }
    function global:Initialize-UvProject { & $global:UV init @args }
    function global:Add-UvPackage { & $global:UV add @args }
    function global:Remove-UvPackage { & $global:UV remove @args }
    function global:Get-UvVersion { & $global:UV version @args }
    function global:Sync-UvProject { & $global:UV sync @args }
    function global:Lock-UvProject { & $global:UV lock @args }
    function global:Export-UvProject { & $global:UV export @args }
    function global:Show-UvTree { & $global:UV tree @args }
    function global:Invoke-UvTool { & $global:UV tool @args }
    function global:Invoke-UvPython { & $global:UV python @args }
    function global:Invoke-UvPip { & $global:UV pip @args }
    function global:New-UvVenv { & $global:UV venv @args }
    function global:Build-UvProject { & $global:UV build @args }
    function global:Publish-UvProject { & $global:UV publish @args }
    function global:Clear-UvCache { & $global:UV cache @args }
    function global:Update-UvSelf { & $global:UV self @args }
    function global:Get-UvHelp { & $global:UV help @args }
        
    # Check if uvx.exe exists in the centralized venv (newer approach)
    $uvxPath = Join-Path $centralVenv "Scripts\uvx.exe"
    if (Test-Path $uvxPath) {
        $global:UVX = $uvxPath
        function global:Invoke-Uvx { & $global:UVX @args }
        Write-Info "Found dedicated uvx.exe in centralized environment"
    }
    else {
        # Fallback to uv tool run
        $global:UVX = "$uvPath tool run"
        function global:Invoke-Uvx { & $global:UV tool run @args }
        Write-Info "Using 'uv tool run' for uvx functionality"
    }
        
    # Create agent-specific aliases for the centralized environment
    function global:Install-AgentPackage { & $global:UV pip --python $centralVenv @args }
    function global:Invoke-AgentRun { & $global:UV run --python $centralVenv @args }
    function global:Invoke-AgentPython { & $global:UvPython @args }
        
    # Set up aliases for common tools found in the venv
    $venvScripts = Join-Path $centralVenv "Scripts"
    Write-Info "Discovering installed executables in centralized environment..."
        
    # Get all .exe files in Scripts directory
    $allExecutables = @()
    if (Test-Path $venvScripts) {
        try {
            $allExecutables = Get-ChildItem -Path $venvScripts -Filter "*.exe" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
            Write-Info "Found $($allExecutables.Count) executables in centralized environment"
        }
        catch {
            Write-Warning "Could not enumerate executables in Scripts directory: $_"
        }
    }
        
    # Common tools to check for
    $toolPaths = @{
        'agent-memory-server' = Join-Path $venvScripts "agent-memory-server.exe"
        'agent-memory'        = Join-Path $venvScripts "agent-memory.exe"
        'fastapi'             = Join-Path $venvScripts "fastapi.exe"
        'uvicorn'             = Join-Path $venvScripts "uvicorn.exe"
        'openai'              = Join-Path $venvScripts "openai.exe"
        'transformers-cli'    = Join-Path $venvScripts "transformers-cli.exe"
        'huggingface-cli'     = Join-Path $venvScripts "huggingface-cli.exe"
        'redis-cli'           = Join-Path $venvScripts "redis-cli.exe"
        'pytest'              = Join-Path $venvScripts "pytest.exe"
        'pip'                 = Join-Path $venvScripts "pip.exe"
    }
        
    # Create functions for installed tools using global variable references
    foreach ($toolName in $toolPaths.Keys) {
        $toolPath = $toolPaths[$toolName]
        if (Test-Path $toolPath) {
            switch ($toolName) {
                'agent-memory-server' {
                    $global:AgentMemoryServerExe = $toolPath
                    function global:Start-AgentMemoryServer { & $global:AgentMemoryServerExe @args }
                    Set-Alias -Name agent-memory-server -Value Start-AgentMemoryServer -Scope Global
                }
                'agent-memory' {
                    $global:AgentMemoryExe = $toolPath
                    function global:Start-AgentMemory { & $global:AgentMemoryExe @args }
                    Set-Alias -Name agent-memory -Value Start-AgentMemory -Scope Global
                }
                'fastapi' {
                    $global:FastAPIExe = $toolPath
                    function global:Start-FastAPI { & $global:FastAPIExe @args }
                }
                'uvicorn' {
                    $global:UvicornExe = $toolPath
                    function global:Start-Uvicorn { & $global:UvicornExe @args }
                    Set-Alias -Name uvicorn -Value Start-Uvicorn -Scope Global
                }
                'openai' {
                    $global:OpenAIExe = $toolPath
                    function global:Invoke-OpenAI { & $global:OpenAIExe @args }
                    Set-Alias -Name openai -Value Invoke-OpenAI -Scope Global
                }
                'transformers-cli' {
                    $global:TransformersExe = $toolPath
                    function global:Invoke-TransformersCli { & $global:TransformersExe @args }
                }
                'huggingface-cli' {
                    $global:HuggingFaceExe = $toolPath
                    function global:Invoke-HuggingFaceCli { & $global:HuggingFaceExe @args }
                }
                'redis-cli' {
                    $global:RedisCliExe = $toolPath
                    function global:Invoke-RedisCli { & $global:RedisCliExe @args }
                }
                'pytest' {
                    $global:PytestExe = $toolPath
                    function global:Invoke-Pytest { & $global:PytestExe @args }
                }
                'pip' {
                    $global:PipExe = $toolPath
                    function global:Invoke-Pip { & $global:PipExe @args }
                }
            }
            Write-Info "Configured alias for: $toolName"
        }
    }
        
    # Create simple aliases that don't conflict with PowerShell cmdlet naming
    Set-Alias -Name uvx -Value Invoke-Uvx -Scope Global
    Set-Alias -Name uv-run -Value Invoke-UvRun -Scope Global
    Set-Alias -Name uv-pip -Value Invoke-UvPip -Scope Global
    Set-Alias -Name uv-venv -Value New-UvVenv -Scope Global
    Set-Alias -Name uv-python -Value Invoke-UvPython -Scope Global
    Set-Alias -Name uv-tool -Value Invoke-UvTool -Scope Global
    Set-Alias -Name uv-init -Value Initialize-UvProject -Scope Global
    Set-Alias -Name uv-add -Value Add-UvPackage -Scope Global
    Set-Alias -Name uv-remove -Value Remove-UvPackage -Scope Global
    Set-Alias -Name uv-sync -Value Sync-UvProject -Scope Global
    Set-Alias -Name uv-lock -Value Lock-UvProject -Scope Global
    Set-Alias -Name uv-tree -Value Show-UvTree -Scope Global
    Set-Alias -Name agent-pip -Value Install-AgentPackage -Scope Global
    Set-Alias -Name agent-run -Value Invoke-AgentRun -Scope Global
    Set-Alias -Name agent-python -Value Invoke-AgentPython -Scope Global
        
    # Additional tool aliases if available - updated to use the new discovery system
    # These are already set up in the loop above
        
    Write-Success "UV command aliases configured successfully"
    Write-Host ""
    Write-Host "Available UV Aliases:" -ForegroundColor Cyan
    Write-Host "  Core UV Commands:" -ForegroundColor Yellow
    Write-Host "    uvx                - Execute packages with UV" -ForegroundColor Green
    Write-Host "    uv-run             - Run commands in UV environment" -ForegroundColor Green
    Write-Host "    uv-pip             - UV pip package management" -ForegroundColor Green
    Write-Host "    uv-venv            - UV virtual environment management" -ForegroundColor Green
    Write-Host "    uv-python          - UV Python installation management" -ForegroundColor Green
    Write-Host "    uv-tool            - UV tool management" -ForegroundColor Green
    Write-Host "    uv-init, uv-add, uv-remove, uv-sync, uv-lock, uv-tree" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Agent-Specific Commands:" -ForegroundColor Yellow
    Write-Host "    agent-pip          - Install packages in centralized agent venv" -ForegroundColor Green
    Write-Host "    agent-run          - Run commands with centralized agent venv" -ForegroundColor Green
    Write-Host "    agent-python       - Direct access to centralized agent Python" -ForegroundColor Green
    if (Test-Path (Join-Path $venvScripts "agent-memory.exe")) {
        Write-Host "    agent-memory       - Agent memory server executable" -ForegroundColor Green
    }
    if (Test-Path (Join-Path $venvScripts "agent-memory-server.exe")) {
        Write-Host "    agent-memory-server - Agent memory server main executable" -ForegroundColor Green
    }
    Write-Host ""
    Write-Host "  Installed Tools:" -ForegroundColor Yellow
    if (Test-Path (Join-Path $venvScripts "uvicorn.exe")) {
        Write-Host "    uvicorn            - ASGI server" -ForegroundColor Green
    }
    if (Test-Path (Join-Path $venvScripts "openai.exe")) {
        Write-Host "    openai             - OpenAI CLI" -ForegroundColor Green
    }
    if (Test-Path (Join-Path $venvScripts "transformers-cli.exe")) {
        Write-Host "    transformers-cli   - Hugging Face Transformers CLI" -ForegroundColor Green
    }
    if (Test-Path (Join-Path $venvScripts "huggingface-cli.exe")) {
        Write-Host "    huggingface-cli    - Hugging Face Hub CLI" -ForegroundColor Green
    }
    if (Test-Path (Join-Path $venvScripts "pytest.exe")) {
        Write-Host "    pytest             - Python testing framework" -ForegroundColor Green
    }
    if (Test-Path (Join-Path $venvScripts "redis-cli.exe")) {
        Write-Host "    redis-cli          - Redis command line interface" -ForegroundColor Green
    }
    Write-Host ""
        
    # Test some basic UV commands
    Write-Info "Testing UV command aliases..."
    try {
        $uvVersion = & $global:UV --version 2>&1
        Write-Success "UV version: $uvVersion"
            
        & $global:UV python list 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Success "UV Python management working"
        }
            
        # Test uvx functionality
        Write-Info "Testing uvx functionality..."
        if (Test-Path $uvxPath) {
            & $global:UVX --help 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Success "uvx executable working (using dedicated uvx.exe)"
            }
            else {
                Write-Warning "uvx executable test returned non-zero exit code"
            }
        }
        else {
            & $global:UV tool --help 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Success "uvx functionality working (using 'uv tool')"
            }
            else {
                Write-Warning "uv tool test returned non-zero exit code"
            }
        }
    }
    catch {
        Write-Warning "Error testing UV commands: $_"
    }
        
    # Display comprehensive summary of discovered tools
    Write-Host ""
    Write-Host "Discovered Executables Summary:" -ForegroundColor Cyan
    if ($allExecutables.Count -gt 0) {
        $allExecutables | Sort-Object | ForEach-Object {
            $toolName = $_ -replace "\.exe$", ""
            Write-Host "  $toolName" -ForegroundColor Gray
        }
    }
    else {
        Write-Host "  No executables found in Scripts directory" -ForegroundColor Yellow
    }
}
catch {
    Write-Warning "Could not find UV executable in PATH: $_"
    Write-Host "Please ensure UV is properly installed and in your PATH" -ForegroundColor Yellow
}
    
Write-Success "UV environment setup completed!"
Write-Host ""
Write-Host "Centralized Environment Details:" -ForegroundColor Cyan
Write-Host "  Location: $centralVenv" -ForegroundColor Green
Write-Host "  Python: $(& $uvPythonPath --version 2>&1)" -ForegroundColor Green
Write-Host "  UV Python Path: $uvPythonPath" -ForegroundColor Green
Write-Host "  Packages: Use 'uv pip list --python $centralVenv' to view installed packages" -ForegroundColor Green
Write-Host ""
Write-Host "Environment Variables and Aliases Set:" -ForegroundColor Cyan
Write-Host "  `$global:UvPython = $global:UvPython" -ForegroundColor Green
Write-Host "  `$global:UV = $global:UV" -ForegroundColor Green
if (Test-Path (Join-Path $centralVenv "Scripts\uvx.exe")) {
    Write-Host "  `$global:UVX = $global:UVX (dedicated uvx.exe)" -ForegroundColor Green
}
else {
    Write-Host "  `$global:UVX = $global:UVX (uv tool run)" -ForegroundColor Green
}
Write-Host "  UV aliases: uvx, uv-run, uv-pip, uv-venv, uv-python, uv-tool, etc." -ForegroundColor Green
Write-Host "  Agent aliases: agent-pip, agent-run, agent-python, agent-memory" -ForegroundColor Green
if (Test-Path (Join-Path $centralVenv "Scripts\uvicorn.exe")) {
    Write-Host "  Tool aliases: uvicorn, openai, transformers-cli, huggingface-cli, pytest, redis-cli" -ForegroundColor Green
}
else {
    Write-Host "  Tool aliases: (install tools to see available aliases)" -ForegroundColor Green
}
Write-Host ""
Write-Host "Usage Examples:" -ForegroundColor Cyan
Write-Host "  uvx ruff check .                    # Run ruff with uvx" -ForegroundColor Yellow
Write-Host "  uv-tool run black .                 # Run black formatter" -ForegroundColor Yellow
Write-Host "  agent-pip install numpy             # Install in centralized venv" -ForegroundColor Yellow
Write-Host "  agent-run python -c 'import sys; print(sys.version)'" -ForegroundColor Yellow
Write-Host "  agent-python --version              # Direct Python access" -ForegroundColor Yellow
if (Test-Path (Join-Path $centralVenv "Scripts\agent-memory.exe")) {
    Write-Host "  agent-memory run-all                # Start agent memory server" -ForegroundColor Yellow
}
if (Test-Path (Join-Path $centralVenv "Scripts\agent-memory-server.exe")) {
    Write-Host "  agent-memory-server run-all         # Start agent memory server" -ForegroundColor Yellow
}
if (Test-Path (Join-Path $centralVenv "Scripts\uvicorn.exe")) {
    Write-Host "  uvicorn main:app --reload          # Start FastAPI server" -ForegroundColor Yellow
}
Write-Host ""
    
return $true
}

function Test-RedisSetup {
    <#
    .SYNOPSIS
    Tests Redis setup using the RedisUtilities module
    
    .DESCRIPTION
    Wrapper function that uses the RedisUtilities PowerShell module for testing Redis setup
    #>
    
    Write-Info "Testing Redis setup..."
    
    # Check if RedisUtilities module is loaded
    if (-not (Get-Module -Name RedisUtilities)) {
        Write-Error "RedisUtilities module is not loaded"
        return $false
    }
    
    try {
        # Use the module function
        $result = Test-RedisSetup
        return $result
    }
    catch {
        Write-Error "Error testing Redis setup: $_"
        return $false
    }
}

function Download-RedisBinaries {
    <#
    .SYNOPSIS
    Downloads Redis binaries for Windows
    
    .DESCRIPTION
    Downloads Redis server and CLI binaries from a reliable source or GitHub releases
    
    .PARAMETER DownloadPath
    Directory to download and extract Redis binaries
    
    .PARAMETER ForceDownload
    Force re-download even if binaries exist
    
    .OUTPUTS
    Boolean indicating successful download and extraction
    #>
    
    [CmdletBinding()]
    param(
        [string]$DownloadPath = (Get-Location).Path,
        [switch]$ForceDownload
    )
    
    Write-Info "Downloading Redis binaries for Windows..."
    
    # Define Redis download URLs and options
    $redisDownloads = @{
        "Memurai"               = @{
            Url         = "https://github.com/Memurai/memurai/releases/latest/download/Memurai-Developer.zip"
            Description = "Memurai - Redis-compatible Windows binary"
            Executables = @("memurai.exe", "memurai-cli.exe")
            AliasMap    = @{
                "memurai.exe"     = "redis-server.exe"
                "memurai-cli.exe" = "redis-cli.exe"
            }
        }
        "Redis-Windows-Service" = @{
            Url         = "https://github.com/redis-windows/redis-windows/releases/latest/download/redis-windows.zip"
            Description = "Redis Windows Service binaries"
            Executables = @("redis-server.exe", "redis-cli.exe")
            AliasMap    = @{
            }
        }
        "Tporadowski-Redis"     = @{
            Url         = "https://github.com/tporadowski/redis/releases/download/v5.0.14.1/Redis-x64-5.0.14.1.zip"
            Description = "Tporadowski Redis 5.0.14.1 (stable Windows port)"
            Executables = @("redis-server.exe", "redis-cli.exe", "redis-check-aof.exe", "redis-check-rdb.exe")
            AliasMap    = @{
            }
        }
    }
    
    # Check if Redis binaries already exist
    $existingBinaries = Find-RedisExecutables -BasePath $DownloadPath
    if ($existingBinaries.RedisServer -and $existingBinaries.RedisCli -and -not $ForceDownload) {
        Write-Success "Redis binaries already exist:"
        Write-Host "  Redis Server: $($existingBinaries.RedisServer)" -ForegroundColor Green
        Write-Host "  Redis CLI: $($existingBinaries.RedisCli)" -ForegroundColor Green
        return $true
    }
    
    # Determine download method preference
    $downloadMethods = @()
    
    # Check for aria2c (fastest)
    try {
        & aria2c --version 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $downloadMethods += "aria2c"
            Write-Info "Found aria2c - will use for fastest download"
        }
    }
    catch {
        # aria2c not available
    }
    
    # Check for curl
    try {
        & curl --version 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $downloadMethods += "curl"
            Write-Info "Found curl - available for download"
        }
    }
    catch {
        # curl not available
    }
    
    # PowerShell Invoke-WebRequest (always available)
    $downloadMethods += "Invoke-WebRequest"
    
    Write-Info "Available download methods: $($downloadMethods -join ', ')"
    
    # Try each Redis source until one works
    foreach ($source in $redisDownloads.Keys) {
        $downloadInfo = $redisDownloads[$source]
        
        Write-Info "Attempting to download from: $($downloadInfo.Description)"
        Write-Info "URL: $($downloadInfo.Url)"
        
        $tempDir = Join-Path $env:TEMP "redis-download-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        $zipFile = Join-Path $tempDir "redis.zip"
        
        try {
            # Create temporary directory
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
            
            $downloadSuccess = $false
            
            # Try download methods in order of preference
            foreach ($method in $downloadMethods) {
                Write-Info "Trying download with: $method"
                
                try {
                    switch ($method) {
                        "aria2c" {
                            & aria2c --dir=$tempDir --out="redis.zip" --max-connection-per-server=10 --split=10 $downloadInfo.Url
                            if ($LASTEXITCODE -eq 0 -and (Test-Path $zipFile)) {
                                $downloadSuccess = $true
                                Write-Success "Downloaded successfully with aria2c"
                                break
                            }
                        }
                        "curl" {
                            & curl -L -o $zipFile $downloadInfo.Url
                            if ($LASTEXITCODE -eq 0 -and (Test-Path $zipFile)) {
                                $downloadSuccess = $true
                                Write-Success "Downloaded successfully with curl"
                                break
                            }
                        }
                        "Invoke-WebRequest" {
                            Invoke-WebRequest -Uri $downloadInfo.Url -OutFile $zipFile -UseBasicParsing
                            if (Test-Path $zipFile) {
                                $downloadSuccess = $true
                                Write-Success "Downloaded successfully with Invoke-WebRequest"
                                break
                            }
                        }
                    }
                }
                catch {
                    Write-Warning "Download failed with $method`: $_"
                    continue
                }
            }
            
            if (-not $downloadSuccess) {
                Write-Warning "All download methods failed for $source"
                continue
            }
            
            # Verify download
            if (-not (Test-Path $zipFile) -or (Get-Item $zipFile).Length -eq 0) {
                Write-Warning "Downloaded file is empty or missing for $source"
                continue
            }
            
            Write-Info "Extracting Redis binaries..."
            
            # Extract ZIP file
            try {
                Expand-Archive -Path $zipFile -DestinationPath $tempDir -Force
                Write-Success "Extracted archive successfully"
            }
            catch {
                Write-Warning "Failed to extract archive for $source`: $_"
                continue
            }
            
            # Find and copy executables
            $foundExecutables = @()
            $allFiles = Get-ChildItem -Path $tempDir -Recurse -File
            
            foreach ($expectedExe in $downloadInfo.Executables) {
                $foundFile = $allFiles | Where-Object { $_.Name -eq $expectedExe } | Select-Object -First 1
                if ($foundFile) {
                    $foundExecutables += $foundFile
                    Write-Info "Found: $($foundFile.Name) at $($foundFile.FullName)"
                }
            }
            
            if ($foundExecutables.Count -eq 0) {
                Write-Warning "No expected executables found in $source archive"
                continue
            }
            
            # Copy executables to target directory
            $copySuccess = $true
            foreach ($exe in $foundExecutables) {
                try {
                    # Determine target name (check for alias mapping)
                    $targetName = $exe.Name
                    if ($downloadInfo.AliasMap.ContainsKey($exe.Name)) {
                        $targetName = $downloadInfo.AliasMap[$exe.Name]
                    }
                    
                    $targetPath = Join-Path $DownloadPath $targetName
                    Copy-Item -Path $exe.FullName -Destination $targetPath -Force
                    Write-Success "Copied $($exe.Name) to $targetName"
                }
                catch {
                    Write-Error "Failed to copy $($exe.Name): $_"
                    $copySuccess = $false
                    break
                }
            }
            
            if ($copySuccess) {
                Write-Success "Redis binaries downloaded and installed successfully!"
                Write-Host "Source: $($downloadInfo.Description)" -ForegroundColor Green
                
                # Verify installation
                $verifyBinaries = Find-RedisExecutables -BasePath $DownloadPath
                if ($verifyBinaries.RedisServer -and $verifyBinaries.RedisCli) {
                    Write-Success "Verification passed - Redis binaries are ready to use"
                    
                    # Clean up temporary directory
                    try {
                        Remove-Item -Path $tempDir -Recurse -Force
                    }
                    catch {
                        Write-Warning "Could not clean up temporary directory: $tempDir"
                    }
                    
                    return $true
                }
                else {
                    Write-Warning "Verification failed - some binaries may be missing"
                }
            }
        }
        catch {
            Write-Warning "Error downloading from $source`: $_"
        }
        finally {
            # Clean up temporary directory
            if (Test-Path $tempDir) {
                try {
                    Remove-Item -Path $tempDir -Recurse -Force
                }
                catch {
                    Write-Warning "Could not clean up temporary directory: $tempDir"
                }
            }
        }
    }
    
    Write-Error "Failed to download Redis binaries from all sources"
    Write-Host ""
    Write-Host "Manual Download Options:" -ForegroundColor Yellow
    Write-Host "1. Memurai Developer (Redis-compatible): https://www.memurai.com/get-memurai" -ForegroundColor Cyan
    Write-Host "2. Tporadowski Redis Windows Port: https://github.com/tporadowski/redis/releases" -ForegroundColor Cyan
    Write-Host "3. Microsoft Redis Windows Service: https://github.com/redis-windows/redis-windows" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Please download and extract redis-server.exe and redis-cli.exe to the current directory." -ForegroundColor Yellow
    
    return $false
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
    Write-Host "  .\build.ps1 -SetupUvEnvironment    - Setup centralized UV environment"
    Write-Host "  .\build.ps1 -Help                  - Show this help"
    Write-Host ""
    Write-Host "Parameters:" -ForegroundColor Yellow
    Write-Host "  -RedisPort [port]         - Redis port (default: 6379)" -ForegroundColor Yellow
    Write-Host "  -AgentMemoryPort [port]   - Agent memory server port (default: 8000)" -ForegroundColor Yellow
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
    Write-Host "13. Setup centralized UV environment"
    Write-Host "14. Show Redis information"
    Write-Host "15. Start Redis server"
    Write-Host "16. Stop Redis server"
    Write-Host "17. Download Redis binaries (auto-detect best source)"
    Write-Host "18. Exit"
    Write-Host ""
    
    $choice = Read-Host "Enter your choice (1-18)"
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

if ($SetupUvEnvironment) {
    Setup-UvEnvironment
    exit 0
}

if ($TestRedis) {
    Test-RedisSetup
    exit 0
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
        Start-RedisServer -ConfigPath $configPath
    }
    else {
        Write-Error "RedisUtilities module not loaded"
    }
    exit 0
}

if ($StopRedis) {
    if (Get-Module -Name RedisUtilities) {
        Stop-RedisServer
    }
    else {
        Write-Error "RedisUtilities module not loaded"
    }
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
        "13" {
            Setup-UvEnvironment
        }
        "14" {
            if (Get-Module -Name RedisUtilities) {
                Show-RedisInfo
            }
            else {
                Write-Error "RedisUtilities module not loaded"
            }
        }
        "15" {
            if (Get-Module -Name RedisUtilities) {
                $configPath = if (Test-Path "redis-agent.conf") { "redis-agent.conf" } else { "redis.conf" }
                Start-RedisServer -ConfigPath $configPath
            }
            else {
                Write-Error "RedisUtilities module not loaded"
            }
        }
        "16" {
            if (Get-Module -Name RedisUtilities) {
                Stop-RedisServer
            }
            else {
                Write-Error "RedisUtilities module not loaded"
            }
        }
        "17" {
            Download-RedisBinaries -DownloadPath (Get-Location).Path
        }
        "18" { break }
        default { Write-Warning "Invalid choice. Please select 1-14." }
    }
    
    if ($choice -ne "14") {
        Write-Host ""
        Read-Host "Press Enter to continue..."
    }
    
} while ($choice -ne "14")

Show-Summary
Write-Host "Goodbye!" -ForegroundColor Cyan
