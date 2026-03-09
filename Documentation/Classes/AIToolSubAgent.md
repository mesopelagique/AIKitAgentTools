# AIToolSubAgent

`AIToolSubAgent` manages isolated child agent sessions.

Each sub-agent has:

- its own system prompt
- explicit allowed tool list
- bounded limits (tool calls, timeout, tokens)
- independent run history

## Constructor

```4d
var $sub:=cs.AIToolSubAgent.new({ \
  client: $client; \
  toolRegistry: { \
    duckduckgo_search: $searchTool; \
    web_fetch: $fetchTool \
  }; \
  defaultMaxParallel: 2 \
})
```

## Tool Functions

### subagent_create({name, systemPrompt, allowedTools, model, limits})

Creates a new sub-agent and returns `agentId`.

### subagent_run({agentId, task, input, timeoutSec})

Runs one task in one sub-agent and returns `runId`, status, output/error.

### subagent_run_batch({runs, maxParallel, mergePolicy, reducerPrompt})

Runs a batch of tasks. Current implementation is deterministic and bounded.

- `mergePolicy`: `concat`, `rank`, `vote`, `reducerPrompt`
- `reducerPrompt`: optional prompt used when `mergePolicy = reducerPrompt`

### subagent_get_result({runId})

Returns stored run details.

### subagent_list()

Lists active sub-agents.

### subagent_close({agentId})

Marks a sub-agent as closed.

## Safety

- No nested sub-agent creation by default.
- Tool access is allowlist-only from `toolRegistry`.
- Limits are explicit and configurable.

## See Also

- [AIToolPlanning](AIToolPlanning.md)
- [Security Guide](../tools-security.md)
