# AIToolMemory

The `AIToolMemory` class provides a key-value memory store for AI agents. It lets the LLM save facts, preferences, task context, and other information across tool calls — and optionally persist them to the 4D database via ORDA.

Inspired by the [MCP Knowledge Graph Memory Server](https://github.com/modelcontextprotocol/servers/tree/main/src/memory) and LangChain memory patterns, but simplified to a practical key-value model with categories and search.

> **⚠️ Security:** Memory content is fully controlled by the LLM. It may store prompt injection payloads or sensitive data. See [Security Guide](../tools-security.md).

## Storage Modes

| Mode | Configuration | Description |
|------|--------------|-------------|
| **In-memory** | `cs.agtools.AIToolMemory.new()` | Entries stored in a collection on the class instance. Lost when the process ends. |
| **Database** | `cs.agtools.AIToolMemory.new({dataclass: "Memory"})` | Entries persisted to a 4D dataclass via ORDA. Survives restarts. |

## Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `maxEntries` | Integer | `1000` | Maximum number of memory entries. |
| `maxKeyLength` | Integer | `200` | Maximum key length in characters. |
| `maxValueLength` | Integer | `50000` | Maximum value length in characters (~50KB). |
| `dataclass` | Text | *(empty)* | ORDA dataclass name for persistence. Empty = in-memory only. |
| `fields` | Object | *(see below)* | Field name mapping for the dataclass. |

### Field Mapping (Database Mode)

When using database persistence, the tool needs to know which dataclass attributes to use. Provide a `fields` object in the config:

| Field | Default | Description |
|-------|---------|-------------|
| `key` | `"key"` | Attribute storing the unique memory key. |
| `value` | `"value"` | Attribute storing the memory content. |
| `category` | `"category"` | Attribute storing the category label. |
| `tags` | `"tags"` | Attribute storing comma-separated tags. |
| `createdAt` | `"createdAt"` | Attribute storing creation timestamp. |
| `updatedAt` | `"updatedAt"` | Attribute storing last update timestamp. |

## Constructor

```4d
// In-memory (simplest)
var $memory:=cs.agtools.AIToolMemory.new()
```

```4d
// In-memory with limits
var $memory:=cs.agtools.AIToolMemory.new({ \
  maxEntries: 500; \
  maxKeyLength: 100; \
  maxValueLength: 10000 \
})
```

```4d
// Database-persisted
var $memory:=cs.agtools.AIToolMemory.new({ \
  dataclass: "AgentMemory"; \
  fields: {key: "memKey"; value: "memValue"; category: "memCategory"}; \
  maxEntries: 5000 \
})
```

## Tool Functions

### `memory_store()`

Store a fact or piece of information. If the key already exists, the value is updated.

| Parameter | Type | Description |
|-----------|------|-------------|
| *params.key* | Text | Unique memory key (e.g. `"user_name"`, `"project_deadline"`). |
| *params.value* | Text | The content to store (plain text, JSON string, etc.). |
| *params.category* | Text | Optional category for organisation (e.g. `"preference"`, `"fact"`, `"task"`). |
| *params.tags* | Text | Optional comma-separated tags for filtering (e.g. `"important,personal"`). |
| Result | Text | Confirmation message: "Stored memory '...'" or "Updated memory '...'". |

### `memory_retrieve()`

Retrieve memories by exact key, search query, or category filter.

| Parameter | Type | Description |
|-----------|------|-------------|
| *params.key* | Text | Exact key to look up. Returns a single entry as JSON. |
| *params.query* | Text | Search text — matches across keys, values, categories, and tags (case-insensitive). |
| *params.category* | Text | Filter results to a specific category. Can combine with `query`. |
| Result | Text | JSON object (exact key) or JSON array (search), or an error message. |

At least one of `key`, `query`, or `category` must be provided.

### `memory_list()`

List all stored memory keys with previews, optionally filtered by category.

| Parameter | Type | Description |
|-----------|------|-------------|
| *params.category* | Text | Optional — only list memories in this category. |
| Result | Text | JSON array of `{key, category, preview, updatedAt}` objects. |

### `memory_delete()`

Delete a memory entry by its exact key.

| Parameter | Type | Description |
|-----------|------|-------------|
| *params.key* | Text | The exact key of the memory to delete. |
| Result | Text | Confirmation or error message. |

## Database Schema

If using database persistence, create a dataclass with at least these attributes:

| Attribute | Type | Index | Notes |
|-----------|------|-------|-------|
| `key` | Text | Unique | Primary lookup field. |
| `value` | Text | — | Stores the memory content. Use Text (CLOB) for large values. |
| `category` | Text | Standard | For category filtering. |
| `tags` | Text | — | Comma-separated tags. |
| `createdAt` | Text | — | ISO timestamp. |
| `updatedAt` | Text | Standard | ISO timestamp. |

## Example — In-Memory Agent

```4d
var $client:=cs.AIKit.OpenAI.new()
var $memory:=cs.agtools.AIToolMemory.new()

var $helper:=$client.chat.create("You are a helpful assistant with memory. " + \
  "Use memory_store to remember facts the user shares. " + \
  "Use memory_retrieve to recall information when needed."; \
  {model: "gpt-4o"})
$helper.autoHandleToolCalls:=True
$helper.registerTools($memory)

// First conversation turn
$helper.prompt("My name is Alice and I prefer dark mode.")
// Agent calls: memory_store(key: "user_name", value: "Alice", category: "identity")
// Agent calls: memory_store(key: "ui_preference", value: "dark mode", category: "preference")

// Later turn
$helper.prompt("What's my name?")
// Agent calls: memory_retrieve(key: "user_name") → recalls "Alice"
```

## Example — Database-Persisted Agent

```4d
var $client:=cs.AIKit.OpenAI.new()
var $memory:=cs.agtools.AIToolMemory.new({ \
  dataclass: "AgentMemory"; \
  maxEntries: 10000 \
})

var $helper:=$client.chat.create("You are an assistant with persistent memory. " + \
  "Store important facts so you remember them in future sessions."; \
  {model: "gpt-4o"})
$helper.autoHandleToolCalls:=True
$helper.registerTools($memory)

// Memories survive process restarts because they're stored in the database
$helper.prompt("Remember that our next release date is March 15th.")
```
