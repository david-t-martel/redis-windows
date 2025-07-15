# LLM Agent Integration Guide

This document explains how to integrate Redis for Windows with LLM agents and the agent-memory-server project.

## Overview

This Redis setup is optimized for LLM agent workloads with:
- **High-performance memory management** for vector storage and retrieval
- **Agent-memory-server integration** for conversational and long-term memory
- **Windows-specific optimizations** for reliable service operation
- **Security configurations** suitable for production agent deployments

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   LLM Agent     │───▶│ Agent Memory    │───▶│ Redis Server    │
│   (Claude,      │    │ Server          │    │ (This Project)  │
│   GPT, etc.)    │    │ (Python/REST)   │    │ (C#/.NET)       │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                              │
                              ▼
                       ┌─────────────────┐
                       │ Vector Store    │
                       │ (Redis/Other)   │
                       └─────────────────┘
```

## Quick Setup for Agents

### 1. Install Redis Service

```powershell
# Build and install Redis service
.\build.ps1 -PrepareForAgents

# Or run interactively and choose option 9
.\build.ps1
```

### 2. Configure Agent Memory Server

```powershell
# Setup agent-memory-server integration
.\build.ps1 -ConfigureMemoryServer

# Or manually clone and configure
git clone https://github.com/david-t-martel/agent-memory-server.git %USERPROFILE%\agent-memory-server
cd %USERPROFILE%\agent-memory-server
python -m venv .venv
.venv\Scripts\activate
pip install -e .
```

### 3. Start Services

```powershell
# Start Redis
net start Redis
# OR
.\start.bat

# Start Agent Memory Server
cd %USERPROFILE%\agent-memory-server
.venv\Scripts\activate
agent-memory-server run-all
```

## Agent Configuration

### Connection Settings

Your LLM agents should connect to:

- **Redis Direct**: `redis://localhost:6379`
- **Agent Memory API**: `http://localhost:8000`
- **Agent Memory MCP**: `ws://localhost:8001`

### Environment Variables

Set these in your agent's environment:

```bash
# Redis connection
REDIS_URL=redis://localhost:6379
REDIS_PASSWORD=your_password_if_set

# Agent Memory Server
AGENT_MEMORY_API_URL=http://localhost:8000
AGENT_MEMORY_MCP_URL=ws://localhost:8001

# Optional: Custom ports
REDIS_PORT=6379
AGENT_MEMORY_PORT=8000
AGENT_MEMORY_MCP_PORT=8001
```

## Agent Memory Server Features

The agent-memory-server provides:

### Working Memory
- Session-scoped message storage
- Automatic conversation summarization
- Context window management
- Real-time memory updates

### Long-Term Memory
- Persistent memory across sessions
- Semantic search capabilities
- Vector store integration
- Memory deduplication

### Security & Isolation
- OAuth2/JWT authentication
- User and session isolation
- RBAC permissions
- Secure API endpoints

## Redis Configuration for Agents

The `redis-agent.conf` file is optimized for agent workloads:

### Memory Management
```conf
maxmemory 2gb
maxmemory-policy allkeys-lru
lazyfree-lazy-eviction yes
```

### Persistence
```conf
# Balanced approach for agent data
save 900 1
appendonly yes
appendfsync everysec
```

### Performance
```conf
# Optimized for agent access patterns
hash-max-listpack-entries 512
activedefrag yes
notify-keyspace-events "Ex"
```

## Integration Examples

### Python Agent Example

```python
import redis
import requests
from agent_memory_client import MemoryClient

# Redis connection
redis_client = redis.Redis(host='localhost', port=6379, decode_responses=True)

# Agent Memory Server connection
memory_client = MemoryClient(api_url='http://localhost:8000')

# Store working memory
memory_client.store_working_memory(
    session_id="agent_session_1",
    messages=[{"role": "user", "content": "Hello"}]
)

# Store long-term memory
memory_client.store_long_term_memory(
    user_id="user123",
    content="Important fact about the user",
    metadata={"topic": "preferences"}
)

# Search memories
results = memory_client.search_memories(
    query="user preferences",
    user_id="user123"
)
```

### MCP Integration

For agents supporting Model Context Protocol:

```json
{
  "mcpServers": {
    "agent-memory": {
      "command": "agent-memory-server",
      "args": ["run-mcp"],
      "env": {
        "REDIS_URL": "redis://localhost:6379",
        "MCP_HOST": "localhost",
        "MCP_PORT": "8001"
      }
    }
  }
}
```

### REST API Usage

```bash
# Store working memory
curl -X POST http://localhost:8000/api/v1/working-memory \
  -H "Content-Type: application/json" \
  -d '{
    "session_id": "session123",
    "messages": [{"role": "user", "content": "Hello"}]
  }'

# Search long-term memory
curl -X GET "http://localhost:8000/api/v1/long-term-memory/search?q=user%20preferences&user_id=user123"
```

## Production Deployment

### Security Configuration

1. **Set Redis Password**:
   ```conf
   # In redis-agent.conf
   requirepass your_very_secure_password
   ```

2. **Configure Firewall**:
   ```powershell
   # Allow only local connections
   New-NetFirewallRule -DisplayName "Redis Local" -Direction Inbound -Protocol TCP -LocalPort 6379 -RemoteAddress 127.0.0.1
   ```

3. **Agent Memory Server Security**:
   ```bash
   # Set OAuth2 configuration
   export OAUTH2_PROVIDER_URL=https://your-auth-provider.com
   export JWT_SECRET_KEY=your_jwt_secret
   ```

### Performance Tuning

1. **Memory Allocation**:
   ```conf
   maxmemory 4gb  # Adjust based on available RAM
   maxmemory-policy allkeys-lru
   ```

2. **Connection Limits**:
   ```conf
   maxclients 5000  # Adjust for agent count
   ```

3. **Persistence Tuning**:
   ```conf
   # For high-write agent workloads
   save 300 100
   appendfsync no  # Use with caution
   ```

### Monitoring

1. **Redis Monitoring**:
   ```powershell
   # Check Redis status
   redis-cli.exe info
   redis-cli.exe monitor
   ```

2. **Agent Memory Server Monitoring**:
   ```bash
   # Check API health
   curl http://localhost:8000/health
   
   # View metrics
   curl http://localhost:8000/metrics
   ```

3. **Windows Service Monitoring**:
   ```powershell
   # Check service status
   Get-Service Redis
   
   # View event logs
   Get-EventLog -LogName Application -Source "Redis Service"
   ```

## Troubleshooting

### Common Issues

1. **Redis Connection Failed**:
   ```powershell
   # Check service status
   Get-Service Redis
   
   # Test connection
   redis-cli.exe ping
   
   # Check firewall
   Test-NetConnection -ComputerName localhost -Port 6379
   ```

2. **Agent Memory Server Not Starting**:
   ```bash
   # Check Python environment
   python --version
   
   # Verify installation
   pip list | grep agent-memory
   
   # Check configuration
   cat .env
   ```

3. **High Memory Usage**:
   ```conf
   # Monitor memory usage
   redis-cli.exe info memory
   
   # Adjust limits
   config set maxmemory 1gb
   ```

### Performance Issues

1. **Slow Responses**:
   ```bash
   # Check slow queries
   redis-cli.exe slowlog get 10
   
   # Monitor connections
   redis-cli.exe info clients
   ```

2. **Memory Fragmentation**:
   ```conf
   # Enable active defragmentation
   activedefrag yes
   active-defrag-threshold-lower 10
   ```

## Development Tips

### Testing Agent Integration

```python
# Test script for agent integration
import redis
import time

def test_agent_memory():
    r = redis.Redis(host='localhost', port=6379, decode_responses=True)
    
    # Test basic operations
    r.set('agent:test', 'Hello Agent')
    value = r.get('agent:test')
    print(f"Test value: {value}")
    
    # Test agent memory patterns
    session_id = "test_session"
    r.lpush(f'session:{session_id}:messages', '{"role": "user", "content": "test"}')
    messages = r.lrange(f'session:{session_id}:messages', 0, -1)
    print(f"Session messages: {messages}")

if __name__ == "__main__":
    test_agent_memory()
```

### Custom Agent Integration

```python
class AgentRedisManager:
    def __init__(self, redis_url='redis://localhost:6379'):
        self.redis = redis.from_url(redis_url)
        
    def store_conversation(self, session_id, messages):
        key = f'conversation:{session_id}'
        self.redis.json().set(key, '$', {
            'messages': messages,
            'timestamp': time.time()
        })
        
    def get_conversation(self, session_id):
        key = f'conversation:{session_id}'
        return self.redis.json().get(key, '$')
        
    def search_memories(self, query, user_id):
        # Implement semantic search using Redis vector capabilities
        # or integrate with agent-memory-server
        pass
```

## Next Steps

1. **Scale Horizontally**: Consider Redis Cluster for multiple agents
2. **Add Monitoring**: Implement Prometheus/Grafana monitoring
3. **Backup Strategy**: Setup automated Redis backups
4. **Load Testing**: Test with realistic agent workloads
5. **Security Audit**: Regular security reviews for production use

For more details, see:
- [Redis Documentation](https://redis.io/documentation)
- [Agent Memory Server Docs](https://github.com/david-t-martel/agent-memory-server/docs)
- [Windows Service Management](SETUP_GUIDE.md)
