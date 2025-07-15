# Redis for Windows - AI Coding Agent Instructions

## Project Overview

This project provides a **production-ready Redis server for Windows with native LLM agent integration** through:
- **C# Windows Service Wrapper** (`Program.cs`, `RedisService.csproj`) - Enterprise-grade .NET 8.0 service that manages Redis lifecycle
- **Agent-Memory-Server Integration** - Seamless connection to agent memory management system
- **GitHub Actions Build Pipeline** (`.github/workflows/`) - Automated compilation of Redis from source using MSYS2/Cygwin
- **Multi-deployment Scripts** (`build.ps1`, `build.bat`, `start.bat`) - Comprehensive setup automation with agent support
- **Agent-Optimized Configurations** (`redis-agent.conf`) - Pre-tuned for LLM agent workloads

### Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   LLM Agent     │───▶│ Agent Memory    │───▶│ Redis Server    │
│   (Claude,      │    │ Server          │    │ (This Project)  │
│   GPT, etc.)    │    │ (Python/FastAPI)│    │ (C#/.NET)       │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                              │
                              ▼
                       ┌─────────────────┐
                       │ Vector Store    │
                       │ (Redis/Other)   │
                       └─────────────────┘
```

The wrapper converts Windows paths to Unix-style for MSYS2/Cygwin compatibility:
```csharp
// Critical path conversion pattern in Program.cs
var diskSymbol = configFilePath[..configFilePath.IndexOf(":")];
var fileConf = configFilePath.Replace(diskSymbol + ":", "/cygdrive/" + diskSymbol).Replace("\\", "/");
```

## Development Patterns

### Agent-First Development
- **Agent Integration**: Primary focus on LLM agent memory management and performance
- **Memory Optimization**: Configured for high-throughput agent workloads with vector storage
- **Session Management**: Support for multiple isolated agent sessions
- **Real-time Performance**: Low-latency responses for agent decision-making loops

### Service Lifecycle Management
- **Startup**: The service spawns `redis-server.exe` as child process, redirects output to logging
- **Monitoring**: `ExecuteAsync()` continuously monitors process health with 1-second polling
- **Shutdown**: Graceful termination via `Process.Kill()` with 5-second timeout
- **Logging**: Structured logging to Windows Event Log + file output via Microsoft.Extensions.Logging

### Build System
```powershell
# Agent-optimized workflow
.\build.ps1 -PrepareForAgents         # Complete agent setup with memory server integration
.\build.ps1 -ConfigureMemoryServer    # Setup agent-memory-server integration
.\build.ps1 -BuildOnly               # Build service wrapper only  
.\build.ps1                          # Interactive setup with all options
.\build.ps1 -GitHubWorkflow          # Trigger GitHub Actions build
```

### Service Installation Pattern
```powershell
# Production deployment (requires admin)
sc.exe create Redis binpath="C:\path\RedisService.exe -c C:\path\redis-agent.conf" start=auto
net start Redis
```

## Critical Integration Points

### Agent Memory Server Integration
The project seamlessly integrates with [agent-memory-server](https://github.com/david-t-martel/agent-memory-server):
```powershell
# Automatic setup and configuration
.\build.ps1 -PrepareForAgents -RedisPort 6379 -AgentMemoryPort 8000

# Manual configuration
.\build.ps1 -ConfigureMemoryServer
```

### Command Line Arguments
Service accepts `-c <config_path>` for custom Redis configuration:
```csharp
// Robust argument parsing pattern
for (int i = 0; i < args.Length; i++)
{
    if (args[i] == "-c" && i + 1 < args.Length)
    {
        configFilePath = args[i + 1];
        break;
    }
}
```

### Configuration Management
- **Agent Config**: `redis-agent.conf` optimized for LLM agent workloads
- **Default Config**: `redis.conf` in service directory  
- **Relative Paths**: Resolved against `AppContext.BaseDirectory`
- **Validation**: Configuration validated before Redis startup
- **Agent Settings**: Memory limits, connection pooling, vector storage optimization

### GitHub Actions Workflow Dependencies
The project requires **two-stage build**:
1. **Service Build** (local): `dotnet publish` creates `RedisService.exe`
2. **Redis Binaries** (CI/CD): GitHub Actions compiles `redis-server.exe` using:
   - MSYS2 environment with `gcc make pkg-config libopenssl`
   - Cygwin environment for compatibility layer
   - Cross-compilation from Redis source with Windows-specific patches
   - Agent-optimized build flags and configurations

## Agent-Specific Features

### Memory Management for Agents
```conf
# Agent-optimized Redis configuration
maxmemory 2gb
maxmemory-policy allkeys-lru
lazyfree-lazy-eviction yes
active-defrag yes

# Vector storage optimization
hash-max-listpack-entries 512
set-max-intset-entries 512
zset-max-listpack-entries 128
```

### Agent Session Isolation
```python
# Python agent integration example
import redis
from agent_memory_client import MemoryClient

redis_client = redis.Redis(host='localhost', port=6379)
memory_client = MemoryClient(api_url='http://localhost:8000')

# Store session-specific memory
memory_client.store_working_memory(
    session_id="agent_session_1",
    messages=[{"role": "user", "content": "Hello"}]
)
```

### Performance Monitoring
```powershell
# Monitor agent workload performance
redis-cli.exe info memory
redis-cli.exe slowlog get 10
redis-cli.exe info clients
```

## Testing & Debugging

### Local Development
```powershell
# Test agent integration
.\publish\RedisService.exe -c redis-agent.conf

# Test with agent memory server
.\build.ps1 -PrepareForAgents
.\start-agent.bat

# Full integration test
.\build.ps1  # Select option 11: Test agent-memory-server integration
```

### Agent Development Workflow
```powershell
# Setup development environment
.\build.ps1 -PrepareForAgents

# Start Redis for agents
.\start-agent.bat

# Test agent memory integration
cd %USERPROFILE%\agent-memory-server
.venv\Scripts\activate
agent-memory-server run-all
```

### Windows Service Debugging
- **Event Viewer**: Applications and Services Logs → "Redis Service" entries
- **Process Monitor**: Track file access, registry operations
- **Service Control**: `sc.exe query Redis` for status inspection
- **Agent Metrics**: Monitor memory usage, connection counts, response times

### Common Development Issues
1. **Missing Redis Binaries**: Service logs "Redis server executable not found"
2. **Path Conversion**: Windows→Unix path translation for MSYS2/Cygwin compatibility
3. **Admin Privileges**: Service installation requires elevated PowerShell
4. **Port Conflicts**: Default Redis port 6379 may conflict with existing services
5. **Agent Memory Server**: Python environment and dependency issues
6. **Memory Limits**: Agent workloads may exceed default Redis memory limits

## External Dependencies

### Build-time
- **.NET 8.0 SDK**: Required for service compilation
- **NuGet packages**: `Microsoft.Extensions.Hosting.WindowsServices` for Windows service support
- **PowerShell 5.1+**: For build automation scripts
- **Python 3.8+**: For agent-memory-server integration

### Runtime  
- **Redis Binaries**: `redis-server.exe`, `redis-cli.exe` from GitHub Actions workflow
- **MSYS2/Cygwin DLLs**: Runtime dependencies for Redis binaries
- **Windows Service**: Service Control Manager integration
- **Agent Memory Server**: Python FastAPI application for agent memory management

### CI/CD Pipeline
- **GitHub Actions**: Windows runners with MSYS2/Cygwin toolchains
- **Redis Source**: Downloaded from official Redis repository releases
- **Build Environments**: Dual compilation (MSYS2 + Cygwin) for maximum compatibility
- **Agent Optimization**: Performance tuning for LLM agent workloads

## Code Conventions

- **Logging**: Use structured logging with `ILogger<T>`, avoid `Console.WriteLine`
- **Process Management**: Always use `ProcessStartInfo` with proper working directory
- **Error Handling**: Catch `FileNotFoundException` for missing binaries, log to Event Log
- **Path Handling**: Convert all paths to Unix-style for Redis process compatibility
- **Service State**: Monitor Redis process continuously, implement graceful shutdown
- **Agent Integration**: Follow agent-memory-server API patterns and conventions
- **Performance**: Optimize for agent access patterns (frequent small operations, session isolation)

## Agent Development Guidelines

### Configuration Patterns
```csharp
// Agent-specific configuration loading
var agentConfig = Configuration.GetSection("AgentMemory");
var redisPort = agentConfig.GetValue<int>("RedisPort", 6379);
var memoryServerPort = agentConfig.GetValue<int>("MemoryServerPort", 8000);
```

### Memory Management
```csharp
// Optimize Redis for agent workloads
services.Configure<RedisOptions>(options =>
{
    options.MaxMemory = "2gb";
    options.MaxMemoryPolicy = "allkeys-lru";
    options.LazyFreeeing = true;
    options.ActiveDefragmentation = true;
});
```

### Integration Testing
```csharp
// Test agent-memory-server connectivity
[Test]
public async Task TestAgentMemoryIntegration()
{
    var redis = new RedisClient("localhost:6379");
    var memoryClient = new MemoryClient("http://localhost:8000");
    
    await memoryClient.StoreWorkingMemoryAsync("test_session", messages);
    var retrieved = await memoryClient.GetWorkingMemoryAsync("test_session");
    
    Assert.NotNull(retrieved);
}
```
