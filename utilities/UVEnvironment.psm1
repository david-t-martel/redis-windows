# UVEnvironment.psm1
# ==================
# PowerShell module for UV (ultraviolet) Python package manager integration
# Provides comprehensive environment management, executable discovery, and alias creation

#Requires -Version 5.1

# Module variables
$script:ModuleVersion = "1.0.0"
$script:UVEnvironmentSetup = $false
$script:CentralVenvPath = $null
$script:DiscoveredExecutables = @()

# Export module information
$ModuleInfo = @{
    Version     = $script:ModuleVersion
    Description = "UV Python Environment Management Utilities"
    Author      = "Redis for Windows Project"
    CompanyName = "Redis Windows"
}

# Utility Functions
function Write-UVInfo {
    param([string]$Message)
    Write-Host "[UV-INFO] $Message" -ForegroundColor Blue
}

function Write-UVSuccess {
    param([string]$Message)
    Write-Host "[UV-SUCCESS] $Message" -ForegroundColor Green
}

function Write-UVWarning {
    param([string]$Message)
    Write-Host "[UV-WARNING] $Message" -ForegroundColor Yellow
}

function Write-UVError {
    param([string]$Message)
    Write-Host "[UV-ERROR] $Message" -ForegroundColor Red
}

function Test-UVInstallation {
    <#
    .SYNOPSIS
    Tests if UV (ultraviolet) package manager is installed and available
    
    .DESCRIPTION
    Checks for UV installation, validates Python availability, and optionally installs Python if missing
    
    .OUTPUTS
    Boolean indicating UV availability and readiness
    #>
    
    try {
        $uvVersion = & uv --version 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-UVInfo "UV found: $uvVersion"
            
            # Check UV-managed Python
            $uvPython = & uv python list 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-UVInfo "UV-managed Python versions available"
                return $true
            }
            else {
                Write-UVWarning "UV found but no Python installations detected"
                Write-UVInfo "Installing Python via UV..."
                & uv python install 3.13
                return $true
            }
        }
    }
    catch {
        Write-UVWarning "UV not found. Install from: https://docs.astral.sh/uv/getting-started/installation/"
        return $false
    }
    return $false
}

function Initialize-UVCentralEnvironment {
    <#
    .SYNOPSIS
    Initializes a centralized UV virtual environment
    
    .DESCRIPTION
    Creates and configures a centralized virtual environment using UV-managed Python
    
    .PARAMETER Path
    Path for the centralized virtual environment. Defaults to user's .venv directory
    
    .PARAMETER PythonVersion
    Python version to use. Defaults to 3.13
    
    .PARAMETER Force
    Force recreation of environment if it already exists
    
    .OUTPUTS
    String path to the created virtual environment
    #>
    
    [CmdletBinding()]
    param(
        [string]$Path = (Join-Path $env:USERPROFILE ".venv"),
        [string]$PythonVersion = "3.13",
        [switch]$Force
    )
    
    Write-UVInfo "Initializing centralized UV environment at: $Path"
    
    # Validate UV installation
    if (-not (Test-UVInstallation)) {
        Write-UVError "UV is required for this setup"
        return $null
    }
    
    # Validate and create parent directory if needed
    $parentDir = Split-Path $Path -Parent
    if (-not (Test-Path $parentDir)) {
        Write-UVWarning "Parent directory $parentDir does not exist"
        try {
            New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
            Write-UVInfo "Created parent directory: $parentDir"
        }
        catch {
            Write-UVError "Failed to create parent directory: $_"
            return $null
        }
    }
    
    # Handle existing environment
    if (Test-Path $Path) {
        if ($Force) {
            Write-UVInfo "Removing existing environment (Force parameter specified)"
            Remove-Item -Path $Path -Recurse -Force
        }
        else {
            Write-UVInfo "Centralized virtual environment already exists"
            $pythonPath = Join-Path $Path "Scripts\python.exe"
            if (Test-Path $pythonPath) {
                $pythonVersion = & $pythonPath --version 2>&1
                Write-UVInfo "Using Python: $pythonVersion"
            }
            $script:CentralVenvPath = $Path
            return $Path
        }
    }
    
    # Create new environment
    Write-UVInfo "Creating centralized virtual environment..."
    
    # Ensure Python version is available
    Write-UVInfo "Ensuring Python $PythonVersion is available via UV..."
    & uv python install $PythonVersion 2>&1 | Out-Null
    
    # Create venv with UV-managed Python
    $createResult = & uv venv $Path --python $PythonVersion 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-UVError "Failed to create centralized venv: $createResult"
        return $null
    }
    
    Write-UVSuccess "Centralized virtual environment created with UV-managed Python $PythonVersion"
    $script:CentralVenvPath = $Path
    return $Path
}

function Install-UVPackages {
    <#
    .SYNOPSIS
    Installs packages in the centralized UV environment
    
    .DESCRIPTION
    Installs one or more Python packages using UV in the centralized virtual environment
    
    .PARAMETER Packages
    Array of package names to install
    
    .PARAMETER VenvPath
    Path to virtual environment. Uses centralized path if not specified
    
    .PARAMETER Upgrade
    Upgrade packages if already installed
    
    .OUTPUTS
    Boolean indicating success of installation
    #>
    
    [CmdletBinding()]
    param(
        [string[]]$Packages,
        [string]$VenvPath = $script:CentralVenvPath,
        [switch]$Upgrade
    )
    
    if (-not $VenvPath -or -not (Test-Path $VenvPath)) {
        Write-UVError "Valid virtual environment path required"
        return $false
    }
    
    if (-not $Packages -or $Packages.Count -eq 0) {
        Write-UVWarning "No packages specified for installation"
        return $true
    }
    
    Write-UVInfo "Installing packages in centralized environment: $($Packages -join ', ')"
    
    $successCount = 0
    $totalCount = $Packages.Count
    
    foreach ($package in $Packages) {
        Write-UVInfo "Installing $package with UV..."
        
        $installArgs = @("pip", "install", "--python", $VenvPath, $package)
        if ($Upgrade) {
            $installArgs += "--upgrade"
        }
        
        $installResult = & uv @installArgs 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-UVSuccess "Installed $package"
            $successCount++
        }
        else {
            Write-UVWarning "Failed to install $package : $installResult"
        }
    }
    
    Write-UVInfo "Package installation completed: $successCount/$totalCount successful"
    return ($successCount -eq $totalCount)
}

function Get-UVExecutables {
    <#
    .SYNOPSIS
    Discovers all executables in the UV virtual environment
    
    .DESCRIPTION
    Scans the Scripts directory of the virtual environment and returns information about available executables
    
    .PARAMETER VenvPath
    Path to virtual environment. Uses centralized path if not specified
    
    .OUTPUTS
    Array of executable information objects
    #>
    
    [CmdletBinding()]
    param(
        [string]$VenvPath = $script:CentralVenvPath
    )
    
    if (-not $VenvPath -or -not (Test-Path $VenvPath)) {
        Write-UVWarning "Virtual environment not found at: $VenvPath"
        return @()
    }
    
    $scriptsDir = Join-Path $VenvPath "Scripts"
    if (-not (Test-Path $scriptsDir)) {
        Write-UVWarning "Scripts directory not found: $scriptsDir"
        return @()
    }
    
    Write-UVInfo "Discovering executables in: $scriptsDir"
    
    try {
        $executables = Get-ChildItem -Path $scriptsDir -Filter "*.exe" -ErrorAction SilentlyContinue | 
        ForEach-Object {
            @{
                Name         = $_.BaseName
                FullName     = $_.Name
                Path         = $_.FullName
                Size         = $_.Length
                LastModified = $_.LastWriteTime
            }
        }
        
        Write-UVInfo "Found $($executables.Count) executables"
        $script:DiscoveredExecutables = $executables
        return $executables
    }
    catch {
        Write-UVError "Error discovering executables: $_"
        return @()
    }
}

function Set-UVAliases {
    <#
    .SYNOPSIS
    Creates PowerShell aliases and functions for UV commands and discovered executables
    
    .DESCRIPTION
    Sets up comprehensive alias system for UV commands, Python tools, and discovered executables
    
    .PARAMETER VenvPath
    Path to virtual environment. Uses centralized path if not specified
    
    .PARAMETER IncludeToolAliases
    Whether to create aliases for discovered tools
    
    .OUTPUTS
    Boolean indicating success of alias creation
    #>
    
    [CmdletBinding()]
    param(
        [string]$VenvPath = $script:CentralVenvPath,
        [switch]$IncludeToolAliases = $true
    )
    
    if (-not $VenvPath -or -not (Test-Path $VenvPath)) {
        Write-UVError "Valid virtual environment path required"
        return $false
    }
    
    Write-UVInfo "Setting up UV aliases and functions..."
    
    # Set up Python alias
    $pythonPath = Join-Path $VenvPath "Scripts\python.exe"
    if (Test-Path $pythonPath) {
        $global:UvPython = $pythonPath
        Write-UVSuccess "UV Python configured: $global:UvPython"
    }
    
    # Set up UV command aliases
    try {
        $uvPath = (Get-Command uv -ErrorAction Stop).Source
        Write-UVInfo "UV executable found at: $uvPath"
        
        # Core UV command variables
        $global:UV = $uvPath
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
        
        # PowerShell functions with approved verbs
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
        
        # Check for uvx executable
        $uvxPath = Join-Path $VenvPath "Scripts\uvx.exe"
        if (Test-Path $uvxPath) {
            $global:UVX = $uvxPath
            function global:Invoke-Uvx { & $global:UVX @args }
            Write-UVInfo "Found dedicated uvx.exe"
        }
        else {
            $global:UVX = "$uvPath tool run"
            function global:Invoke-Uvx { & $global:UV tool run @args }
            Write-UVInfo "Using 'uv tool run' for uvx functionality"
        }
        
        # Agent-specific aliases
        function global:Install-AgentPackage { & $global:UV pip --python $VenvPath @args }
        function global:Invoke-AgentRun { & $global:UV run --python $VenvPath @args }
        function global:Invoke-AgentPython { & $global:UvPython @args }
        
        # Simple aliases
        Set-Alias -Name uvx -Value Invoke-Uvx -Scope Global -Force
        Set-Alias -Name uv-run -Value Invoke-UvRun -Scope Global -Force
        Set-Alias -Name uv-pip -Value Invoke-UvPip -Scope Global -Force
        Set-Alias -Name uv-venv -Value New-UvVenv -Scope Global -Force
        Set-Alias -Name uv-python -Value Invoke-UvPython -Scope Global -Force
        Set-Alias -Name uv-tool -Value Invoke-UvTool -Scope Global -Force
        Set-Alias -Name uv-init -Value Initialize-UvProject -Scope Global -Force
        Set-Alias -Name uv-add -Value Add-UvPackage -Scope Global -Force
        Set-Alias -Name uv-remove -Value Remove-UvPackage -Scope Global -Force
        Set-Alias -Name uv-sync -Value Sync-UvProject -Scope Global -Force
        Set-Alias -Name uv-lock -Value Lock-UvProject -Scope Global -Force
        Set-Alias -Name uv-tree -Value Show-UvTree -Scope Global -Force
        Set-Alias -Name agent-pip -Value Install-AgentPackage -Scope Global -Force
        Set-Alias -Name agent-run -Value Invoke-AgentRun -Scope Global -Force
        Set-Alias -Name agent-python -Value Invoke-AgentPython -Scope Global -Force
        
        Write-UVSuccess "UV command aliases configured"
    }
    catch {
        Write-UVError "Could not find UV executable: $_"
        return $false
    }
    
    # Set up tool aliases if requested
    if ($IncludeToolAliases) {
        Set-UVToolAliases -VenvPath $VenvPath
    }
    
    $script:UVEnvironmentSetup = $true
    return $true
}

function Set-UVToolAliases {
    <#
    .SYNOPSIS
    Creates aliases for discovered tools in the virtual environment
    
    .DESCRIPTION
    Scans for common tools and creates PowerShell functions and aliases for them
    
    .PARAMETER VenvPath
    Path to virtual environment. Uses centralized path if not specified
    #>
    
    [CmdletBinding()]
    param(
        [string]$VenvPath = $script:CentralVenvPath
    )
    
    $scriptsDir = Join-Path $VenvPath "Scripts"
    
    # Common tools to create aliases for
    $toolMappings = @{
        'agent-memory-server' = @{ Function = 'Start-AgentMemoryServer'; Alias = 'agent-memory-server' }
        'agent-memory'        = @{ Function = 'Start-AgentMemory'; Alias = 'agent-memory' }
        'fastapi'             = @{ Function = 'Start-FastAPI'; Alias = $null }
        'uvicorn'             = @{ Function = 'Start-Uvicorn'; Alias = 'uvicorn' }
        'openai'              = @{ Function = 'Invoke-OpenAI'; Alias = 'openai' }
        'transformers-cli'    = @{ Function = 'Invoke-TransformersCli'; Alias = $null }
        'huggingface-cli'     = @{ Function = 'Invoke-HuggingFaceCli'; Alias = $null }
        'redis-cli'           = @{ Function = 'Invoke-RedisCli'; Alias = $null }
        'pytest'              = @{ Function = 'Invoke-Pytest'; Alias = $null }
        'pip'                 = @{ Function = 'Invoke-Pip'; Alias = $null }
    }
    
    $configuredTools = @()
    
    foreach ($toolName in $toolMappings.Keys) {
        $toolPath = Join-Path $scriptsDir "$toolName.exe"
        $mapping = $toolMappings[$toolName]
        
        if (Test-Path $toolPath) {
            $globalVar = "global:$($toolName -replace '-','')Exe"
            Set-Variable -Name $globalVar -Value $toolPath -Scope Global
            
            $functionScript = "function global:$($mapping.Function) { & `$$globalVar @args }"
            Invoke-Expression $functionScript
            
            if ($mapping.Alias) {
                Set-Alias -Name $mapping.Alias -Value $mapping.Function -Scope Global -Force
            }
            
            $configuredTools += $toolName
            Write-UVInfo "Configured alias for: $toolName"
        }
    }
    
    if ($configuredTools.Count -gt 0) {
        Write-UVSuccess "Configured $($configuredTools.Count) tool aliases: $($configuredTools -join ', ')"
    }
}

function Initialize-UVEnvironment {
    <#
    .SYNOPSIS
    Complete UV environment initialization and setup
    
    .DESCRIPTION
    Performs full setup of UV environment including venv creation, package installation, and alias configuration
    
    .PARAMETER VenvPath
    Path for virtual environment
    
    .PARAMETER PythonVersion
    Python version to use
    
    .PARAMETER CommonPackages
    Array of common packages to install
    
    .PARAMETER SetupAliases
    Whether to set up aliases
    
    .PARAMETER Force
    Force recreation of environment
    
    .OUTPUTS
    Hashtable with setup results
    #>
    
    [CmdletBinding()]
    param(
        [string]$VenvPath = (Join-Path $env:USERPROFILE ".venv"),
        [string]$PythonVersion = "3.13",
        [string[]]$CommonPackages = @("redis", "fastapi", "uvicorn", "pydantic", "python-dotenv", "httpx", "aiofiles"),
        [switch]$SetupAliases = $true,
        [switch]$Force
    )
    
    Write-UVInfo "Starting complete UV environment initialization..."
    
    $results = @{
        Success           = $false
        VenvPath          = $null
        PackagesInstalled = 0
        AliasesConfigured = $false
        ExecutablesFound  = 0
        Errors            = @()
    }
    
    try {
        # Initialize centralized environment
        $venvPath = Initialize-UVCentralEnvironment -Path $VenvPath -PythonVersion $PythonVersion -Force:$Force
        if (-not $venvPath) {
            $results.Errors += "Failed to initialize virtual environment"
            return $results
        }
        $results.VenvPath = $venvPath
        
        # Install common packages
        if ($CommonPackages -and $CommonPackages.Count -gt 0) {
            Write-UVInfo "Installing common packages..."
            $packageSuccess = Install-UVPackages -Packages $CommonPackages -VenvPath $venvPath
            if ($packageSuccess) {
                $results.PackagesInstalled = $CommonPackages.Count
                Write-UVSuccess "Common packages installed successfully"
            }
            else {
                $results.Errors += "Some packages failed to install"
            }
        }
        
        # Discover executables
        $executables = Get-UVExecutables -VenvPath $venvPath
        $results.ExecutablesFound = $executables.Count
        
        # Set up aliases
        if ($SetupAliases) {
            $aliasSuccess = Set-UVAliases -VenvPath $venvPath -IncludeToolAliases
            $results.AliasesConfigured = $aliasSuccess
        }
        
        $results.Success = $true
        Write-UVSuccess "UV environment initialization completed successfully"
        
    }
    catch {
        $errorMsg = "UV environment initialization failed: $_"
        Write-UVError $errorMsg
        $results.Errors += $errorMsg
    }
    
    return $results
}

function Show-UVEnvironmentInfo {
    <#
    .SYNOPSIS
    Displays comprehensive information about the UV environment
    
    .DESCRIPTION
    Shows environment details, installed packages, available tools, and usage examples
    
    .PARAMETER VenvPath
    Path to virtual environment. Uses centralized path if not specified
    #>
    
    [CmdletBinding()]
    param(
        [string]$VenvPath = $script:CentralVenvPath
    )
    
    if (-not $VenvPath -or -not (Test-Path $VenvPath)) {
        Write-UVWarning "UV environment not initialized or path invalid: $VenvPath"
        return
    }
    
    Write-Host ""
    Write-Host "UV Environment Information" -ForegroundColor Cyan
    Write-Host "=========================" -ForegroundColor Cyan
    Write-Host ""
    
    # Environment details
    Write-Host "Environment Details:" -ForegroundColor Yellow
    Write-Host "  Location: $VenvPath" -ForegroundColor Green
    
    $pythonPath = Join-Path $VenvPath "Scripts\python.exe"
    if (Test-Path $pythonPath) {
        $pythonVersion = & $pythonPath --version 2>&1
        Write-Host "  Python: $pythonVersion" -ForegroundColor Green
        Write-Host "  Python Path: $pythonPath" -ForegroundColor Green
    }
    
    # UV version
    try {
        $uvVersion = & uv --version 2>&1
        Write-Host "  UV Version: $uvVersion" -ForegroundColor Green
    }
    catch {
        Write-Host "  UV Version: Not available" -ForegroundColor Red
    }
    
    Write-Host ""
    
    # Available aliases
    Write-Host "Available Aliases:" -ForegroundColor Yellow
    Write-Host "  Core UV Commands:" -ForegroundColor Cyan
    Write-Host "    uvx, uv-run, uv-pip, uv-venv, uv-python, uv-tool" -ForegroundColor Green
    Write-Host "    uv-init, uv-add, uv-remove, uv-sync, uv-lock, uv-tree" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Agent-Specific Commands:" -ForegroundColor Cyan
    Write-Host "    agent-pip, agent-run, agent-python" -ForegroundColor Green
    
    # Check for tool aliases
    $scriptsDir = Join-Path $VenvPath "Scripts"
    $toolAliases = @()
    
    $commonTools = @("uvicorn", "openai", "agent-memory", "agent-memory-server", "fastapi", "pytest")
    foreach ($tool in $commonTools) {
        $toolPath = Join-Path $scriptsDir "$tool.exe"
        if (Test-Path $toolPath) {
            $toolAliases += $tool
        }
    }
    
    if ($toolAliases.Count -gt 0) {
        Write-Host ""
        Write-Host "  Available Tools:" -ForegroundColor Cyan
        Write-Host "    $($toolAliases -join ', ')" -ForegroundColor Green
    }
    
    Write-Host ""
    
    # Usage examples
    Write-Host "Usage Examples:" -ForegroundColor Yellow
    Write-Host "  uvx ruff check .                    # Run ruff with uvx" -ForegroundColor Gray
    Write-Host "  uv-tool run black .                 # Run black formatter" -ForegroundColor Gray
    Write-Host "  agent-pip install numpy             # Install in centralized venv" -ForegroundColor Gray
    Write-Host "  agent-run python -c 'print(\"Hello\")'# Run Python in centralized venv" -ForegroundColor Gray
    Write-Host "  agent-python --version              # Direct Python access" -ForegroundColor Gray
    
    if ("uvicorn" -in $toolAliases) {
        Write-Host "  uvicorn main:app --reload          # Start FastAPI server" -ForegroundColor Gray
    }
    if ("agent-memory" -in $toolAliases) {
        Write-Host "  agent-memory run-all                # Start agent memory server" -ForegroundColor Gray
    }
    
    Write-Host ""
    
    # Discovered executables
    $executables = Get-UVExecutables -VenvPath $VenvPath
    if ($executables.Count -gt 0) {
        Write-Host "Discovered Executables ($($executables.Count)):" -ForegroundColor Yellow
        $executables | Sort-Object Name | ForEach-Object {
            Write-Host "  $($_.Name)" -ForegroundColor Gray
        }
    }
    
    Write-Host ""
}

function Test-UVEnvironment {
    <#
    .SYNOPSIS
    Tests the UV environment setup and functionality
    
    .DESCRIPTION
    Performs comprehensive testing of UV installation, environment, and aliases
    
    .PARAMETER VenvPath
    Path to virtual environment. Uses centralized path if not specified
    
    .OUTPUTS
    Boolean indicating overall test success
    #>
    
    [CmdletBinding()]
    param(
        [string]$VenvPath = $script:CentralVenvPath
    )
    
    Write-UVInfo "Testing UV environment..."
    
    $testResults = @{
        UVInstalled      = $false
        EnvironmentValid = $false
        PythonWorking    = $false
        AliasesWorking   = $false
        ToolsAvailable   = 0
    }
    
    # Test UV installation
    $testResults.UVInstalled = Test-UVInstallation
    
    # Test environment
    if ($VenvPath -and (Test-Path $VenvPath)) {
        $testResults.EnvironmentValid = $true
        
        # Test Python
        $pythonPath = Join-Path $VenvPath "Scripts\python.exe"
        if (Test-Path $pythonPath) {
            try {
                $pythonVersion = & $pythonPath --version 2>&1
                if ($pythonVersion -match "Python") {
                    $testResults.PythonWorking = $true
                    Write-UVSuccess "Python working: $pythonVersion"
                }
            }
            catch {
                Write-UVWarning "Python test failed: $_"
            }
        }
    }
    
    # Test aliases
    if ($global:UV -and (Test-Path $global:UV)) {
        try {
            $uvVersion = & $global:UV --version 2>&1
            if ($uvVersion -match "uv") {
                $testResults.AliasesWorking = $true
                Write-UVSuccess "UV aliases working: $uvVersion"
            }
        }
        catch {
            Write-UVWarning "Alias test failed: $_"
        }
    }
    
    # Count available tools
    if ($VenvPath) {
        $executables = Get-UVExecutables -VenvPath $VenvPath
        $testResults.ToolsAvailable = $executables.Count
    }
    
    # Display results
    Write-Host ""
    Write-Host "UV Environment Test Results:" -ForegroundColor Cyan
    Write-Host "  UV Installed:     $(if($testResults.UVInstalled){'✓'}else{'✗'})" -ForegroundColor $(if ($testResults.UVInstalled) { 'Green' }else { 'Red' })
    Write-Host "  Environment:      $(if($testResults.EnvironmentValid){'✓'}else{'✗'})" -ForegroundColor $(if ($testResults.EnvironmentValid) { 'Green' }else { 'Red' })
    Write-Host "  Python Working:   $(if($testResults.PythonWorking){'✓'}else{'✗'})" -ForegroundColor $(if ($testResults.PythonWorking) { 'Green' }else { 'Red' })
    Write-Host "  Aliases Working:  $(if($testResults.AliasesWorking){'✓'}else{'✗'})" -ForegroundColor $(if ($testResults.AliasesWorking) { 'Green' }else { 'Red' })
    Write-Host "  Tools Available:  $($testResults.ToolsAvailable)" -ForegroundColor Green
    Write-Host ""
    
    return ($testResults.UVInstalled -and $testResults.EnvironmentValid -and $testResults.PythonWorking)
}

# Export functions
Export-ModuleMember -Function @(
    'Test-UVInstallation',
    'Initialize-UVCentralEnvironment',
    'Install-UVPackages',
    'Get-UVExecutables',
    'Set-UVAliases',
    'Set-UVToolAliases',
    'Initialize-UVEnvironment',
    'Show-UVEnvironmentInfo',
    'Test-UVEnvironment'
) -Variable @(
    'ModuleInfo'
) -Alias @()
