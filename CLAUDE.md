# Claude's Redis Agent Memory System Setup & Analysis

## Current System Status

✅ **Redis Server**: Running on WSL Ubuntu (PID 584) on localhost:6379  
✅ **Windows Redis Service**: Available but not currently running  
✅ **Agent Memory Server**: Dependencies installed, CLI working, ready for use  
✅ **MCP Integration**: Configured in Claude Desktop (`agent-memory` server)  
🔧 **OpenAI API Key**: Needs to be set in environment variables  

## Project Overview

This setup consists of three main components:

1. **Redis Windows Project** (`T:\projects\redis-windows`): A C#/.NET Redis service optimized for Windows with agent-specific configurations
2. **Agent Memory Server** (`C:\Users\david\agent-memory-server`): Python-based memory management server providing both REST API and MCP interfaces
3. **WSL Redis Instance**: Currently running Redis server that we're using for development

## Architecture Analysis

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Claude Desktop│───▶│ Agent Memory    │───▶│ Redis Server    │
│   (MCP Client)  │    │ Server (MCP)    │    │ (WSL/Windows)   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                              │
                              ▼
                       ┌─────────────────┐
                       │ Vector Store    │
                       │ + Embeddings    │
                       └─────────────────┘
```

## Setup Status & Next Steps

### ✅ Completed
- Redis connection working (localhost:6379)
- Agent memory server Python environment setup with uv
- All dependencies installed (PyTorch, transformers, OpenAI, etc.)
- Redis configuration optimized for agent workloads
- MCP server integration configured in Claude Desktop
- CLI commands verified and working

### 🔧 In Progress
- OpenAI API key configuration (placeholder set for testing)
- Initial testing and validation with Claude Desktop restart required

### 📋 Todo Items

#### Immediate (Today)
1. **Configure OpenAI API Key**
   - Set OPENAI_API_KEY environment variable with actual key
   - Test agent memory server startup with real API key

2. **Test Claude Desktop Integration**
   - Restart Claude Desktop to load new MCP configuration
   - Test memory storage and retrieval functions
   - Validate MCP server connectivity

3. **Validate System Integration**
   - Test working memory operations
   - Test long-term memory storage
   - Verify Redis data persistence

#### Near Term (This Week)
4. **Switch to Windows Redis Service** (Optional)
   - Start Windows Redis service instead of WSL
   - Update configuration accordingly

5. **Production Configuration**
   - Enable Redis authentication
   - Configure proper logging
   - Set up monitoring

6. **Memory System Testing**
   - Test working memory functionality
   - Test long-term memory with embeddings
   - Test semantic search capabilities

#### Long Term (Next Month)
7. **Advanced Features**
   - Configure OAuth2 authentication for production
   - Set up Redis clustering for scalability
   - Add Prometheus monitoring

8. **Integration Optimization**
   - Fine-tune memory window sizes
   - Optimize embedding model selection
   - Configure memory compaction schedules

## Configuration Files

### Agent Memory Server (.env)
```bash
# Redis connection
REDIS_URL=redis://localhost:6379

# Server ports
PORT=8000
MCP_PORT=8001

# Memory settings
LONG_TERM_MEMORY=true
WINDOW_SIZE=12
GENERATION_MODEL=gpt-4o-mini
EMBEDDING_MODEL=text-embedding-3-small

# API Keys
OPENAI_API_KEY=${OPENAI_API_KEY}

# Development Mode
DISABLE_AUTH=true
```

### Claude Desktop MCP Configuration
```json
{
  "mcpServers": {
    "agent-memory": {
      "command": "C:/Users/david/agent-memory-server/.venv/Scripts/python.exe",
      "args": ["-m", "agent_memory_server.cli", "mcp", "--mode", "stdio"],
      "cwd": "C:/Users/david/agent-memory-server",
      "env": {
        "REDIS_URL": "redis://localhost:6379",
        "OPENAI_API_KEY": "${env:OPENAI_API_KEY}",
        "DISABLE_AUTH": "true",
        "PORT": "8000",
        "MCP_PORT": "8001",
        "LONG_TERM_MEMORY": "true",
        "WINDOW_SIZE": "12",
        "GENERATION_MODEL": "gpt-4o-mini",
        "EMBEDDING_MODEL": "text-embedding-3-small"
      }
    }
  }
}
```

### Redis Configuration (redis-agent.conf)
Key optimizations for agent workloads:
- Memory: 2GB limit with LRU eviction
- Persistence: Balanced RDB + AOF
- Vector support: Optimized for embeddings
- Notifications: Keyspace events enabled

## How This Benefits Claude

### 1. **Persistent Context Memory**
I can maintain conversation context across sessions, remembering:
- Previous projects and discussions
- User preferences and patterns
- Historical decisions and rationales
- Long-running task progress

### 2. **Semantic Memory Search**
I can search through past interactions semantically:
- "Find discussions about Redis optimization"
- "Recall previous database design decisions"
- "What did we decide about the authentication setup?"

### 3. **Working Memory Management**
Intelligent context window management:
- Automatic conversation summarization
- Context preservation across long sessions
- Structured memory storage for code projects

### 4. **Enhanced Project Continuity**
- Remember incomplete tasks and todo items
- Track project status across multiple sessions
- Maintain understanding of project architecture

### 5. **Collaborative Intelligence**
- Store and retrieve project documentation
- Remember team preferences and standards
- Track decision history and reasoning

## Usage Examples

### Working Memory Operations
```python
# Store current conversation context
memory_client.store_working_memory(
    session_id="claude_session_1",
    messages=[
        {"role": "user", "content": "Help me setup Redis for LLM agents"},
        {"role": "assistant", "content": "I'll help you configure..."}
    ]
)
```

### Long-Term Memory Storage
```python
# Store important project decisions
memory_client.store_long_term_memory(
    user_id="david",
    content="Redis Windows service uses port 6379, agent-memory-server on 8000",
    metadata={
        "topic": "redis-configuration",
        "project": "agent-memory-server",
        "type": "technical-decision"
    }
)
```

### Semantic Search
```python
# Search for relevant memories
results = memory_client.search_memories(
    query="Redis configuration for Windows",
    user_id="david",
    filters={"project": "agent-memory-server"}
)
```

### Quick Start Commands

#### Test Agent Memory Server CLI
```bash
cd C:\Users\david\agent-memory-server
.venv\Scripts\activate
python -m agent_memory_server.cli --help
python -m agent_memory_server.cli mcp --help
```

#### Test Redis Connection
```bash
python -c "import redis; r = redis.Redis(host='localhost', port=6379); print('Redis:', r.ping())"
```

#### Start MCP Server (for testing)
```bash
$env:OPENAI_API_KEY = "your-actual-key-here"
python -m agent_memory_server.cli mcp --mode stdio
```

#### Test REST API (alternative to MCP)
```bash
python -m agent_memory_server.cli api --port 8000
# Then in another terminal:
curl -X GET http://localhost:8000/health
```

## Current Issues & Solutions

### Issue 1: CLI Commands Hanging
- **Problem**: `agent-memory --help` commands hanging
- **Solution**: Use `python -m agent_memory_server` instead
- **Status**: Workaround identified

### Issue 2: OpenAI API Key
- **Problem**: Placeholder API key in .env
- **Solution**: Set OPENAI_API_KEY environment variable
- **Status**: Configuration updated to use env var

### Issue 3: Unix-style Virtual Environment
- **Problem**: Original .venv was Unix-style
- **Solution**: Recreated using `uv venv` on Windows
- **Status**: ✅ Resolved

## Performance Monitoring

### Redis Metrics to Monitor
- Memory usage: `INFO memory`
- Connection count: `INFO clients`
- Command statistics: `INFO commandstats`
- Keyspace hits/misses: `INFO stats`

### Agent Memory Server Metrics
- API response times
- Memory storage/retrieval latency
- Embedding generation performance
- Background task queue status

## Security Considerations

### Development (Current)
- Authentication disabled (`DISABLE_AUTH=true`)
- Local-only access (127.0.0.1)
- No password protection

### Production (Future)
- OAuth2/JWT authentication
- Redis password protection
- TLS encryption
- Network segmentation

## Integration Roadmap

### Phase 1: Basic Integration (This Week)
- [x] Redis server running
- [x] Agent memory server installed
- [ ] MCP integration with Claude Desktop
- [ ] Basic memory operations working

### Phase 2: Enhanced Features (Next Week)
- [ ] Semantic search optimization
- [ ] Memory compaction scheduling
- [ ] Performance monitoring setup
- [ ] Documentation and examples

### Phase 3: Production Ready (Next Month)
- [ ] Authentication and security
- [ ] High availability setup
- [ ] Backup and recovery procedures
- [ ] Load testing and optimization

## Notes for Future Sessions

### Remember to Check
1. Redis server status (`netstat -an | findstr :6379`)
2. Agent memory server health (`curl http://localhost:8000/health`)
3. MCP connection status in Claude Desktop
4. Environment variables (especially OPENAI_API_KEY)

### Common Commands
```bash
# Start Redis Windows service
net start Redis

# Start agent memory server
cd C:\Users\david\agent-memory-server && .venv\Scripts\activate && python -m agent_memory_server run-all

# Check Redis logs
wsl -e tail -f /var/log/redis/redis-server.log

# Monitor Redis activity
wsl -e redis-cli monitor
```

### Key Files to Monitor
- `C:\Users\david\agent-memory-server\.env` - Environment configuration
- `T:\projects\redis-windows\redis-agent.conf` - Redis configuration  
- `C:\Users\david\AppData\Roaming\Claude\claude_desktop_config.json` - Claude MCP config
- `T:\projects\redis-windows\CLAUDE.md` - This file (update regularly)

---

**Last Updated**: July 15, 2025  
**Status**: MCP integration configured, ready for testing with OpenAI API key  
**Next Steps**: Set OPENAI_API_KEY environment variable and restart Claude Desktop to test integration
