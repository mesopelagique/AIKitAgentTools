# AI Kit Agent Tools

A collection of ready-to-use AI tools for [4D AIKit](https://github.com/4d/4D-AIKit), demonstrating how to give LLMs access to external capabilities using the `OpenAIChatHelper` tool registration system.

> **⚠️ These tools interact with real systems (network, file system, shell, database). Read the [Security Guide](Documentation/tools-security.md) before deploying.**

## Tools

| Tool | Class | Description | 4D API |
|------|-------|-------------|--------|
| **Web Fetch** | `AIToolWebFetch` | Fetch web page content | `4D.HTTPRequest` |
| **Search** | `AIToolSearch` | DuckDuckGo web search | `4D.HTTPRequest` |
| **File System** | `AIToolFileSystem` | Read/write/list files and folders | `4D.File`, `4D.Folder` |
| **Command** | `AIToolCommand` | Execute shell commands | `4D.SystemWorker` |
| **Data** | `AIToolData` | Query 4D database via ORDA | `ds`, `dataClass.query()` |
| **Image** | `AIToolImage` | Generate images from text prompts | `OpenAI.images.generate()` |
| **Calculator** | `AIToolCalculator` | Evaluate math expressions safely | `ExpressionLanguage` |
| **Memory** | `AIToolMemory` | Key-value memory store for agents | In-memory / ORDA |
| **Mail** | `AIToolMail` | Send emails via SMTP | `4D.SMTPTransporter` |

## Quick Start

### 1. Add 4D AIKit as a dependency

This project depends on [4D AIKit](https://github.com/nicgorski/4D-AIKit). The dependency is already declared in `Project/Sources/dependencies.json`.

### 2. Set up your API key

Create a file `~/.openai` containing your OpenAI API key:

```bash
echo "sk-your-api-key-here" > ~/.openai
```

### 3. Register a tool

Each tool class follows the same pattern — it exposes a `tools` collection and handler methods matching tool names. Registration is a single call:

```4d
var $client:=cs.OpenAI.new()
var $helper:=$client.chat.create("You are a helpful assistant."; {model: "gpt-4o-mini"})
$helper.autoHandleToolCalls:=True

// Create and register a tool
var $webFetch:=cs.AIToolWebFetch.new({ \
  allowedDomains: ["*.wikipedia.org"; "httpbin.org"] \
})
$helper.registerTools($webFetch)

// The LLM will automatically use the tool when needed
var $result:=$helper.prompt("Fetch https://httpbin.org/html and summarize it.")
```

### 4. Combine multiple tools

```4d
// Register all tools on a single helper
$helper.registerTools(cs.AIToolWebFetch.new({allowedDomains: ["*.wikipedia.org"]}))
$helper.registerTools(cs.AIToolSearch.new({maxResults: 3}))
$helper.registerTools(cs.AIToolFileSystem.new({allowedPaths: ["/tmp/sandbox/"]; readOnly: False}))
$helper.registerTools(cs.AIToolCommand.new({allowedCommands: ["echo"; "date"; "ls"]}))
$helper.registerTools(cs.AIToolData.new({allowedDataclasses: ["Product"]; maxRecords: 20}))
$helper.registerTools(cs.AIToolImage.new($client; {outputFolder: Folder("/PACKAGE/images")}))
$helper.registerTools(cs.AIToolCalculator.new())

// The LLM orchestrates across all tools
var $result:=$helper.prompt("Search for 4D programming, fetch the top result, and save a summary to /tmp/sandbox/summary.md")
```

See `demo_agent` method for a complete multi-tool example.

## Tool Overview

### AIToolWebFetch

Fetches web page content via `4D.HTTPRequest`.

```4d
var $tool:=cs.AIToolWebFetch.new({ \
  allowedDomains: ["*.wikipedia.org"]; \  // Domain whitelist (⚠️ required for security)
  timeout: 15; \
  maxResponseSize: 50000 \
})
```

**Security:** Domain whitelist, SSRF protection (blocks internal IPs), content-type filtering, response size cap.

### AIToolSearch

Searches the web via DuckDuckGo's HTML endpoint.

```4d
var $tool:=cs.AIToolSearch.new({ \
  maxResults: 5; \
  timeout: 10 \
})
```

**Security:** Query sanitization, result count cap. Note: search results are untrusted (prompt injection risk).

### AIToolFileSystem

File and folder operations using `4D.File` / `4D.Folder`.

```4d
var $tool:=cs.AIToolFileSystem.new({ \
  allowedPaths: ["/Users/me/project/"]; \  // Sandbox (⚠️ required)
  deniedPaths: ["*.env"; "*.key"]; \
  readOnly: True \                          // Disable writes when not needed
})
```

**Tools:** `list_directory`, `read_file`, `write_file`, `create_directory`, `delete_file`, `move_item`, `copy_file`  
**Security:** Path sandbox, path traversal blocking, denied path patterns, read-only mode, file size limit.

### AIToolCommand

Shell command execution via `4D.SystemWorker`.

```4d
var $tool:=cs.AIToolCommand.new({ \
  allowedCommands: ["echo"; "date"; "ls"; "cat"]; \  // Mandatory whitelist
  blockMetacharacters: True; \                         // Block |, ;, &&, etc.
  timeout: 10 \
})
```

**🔴 Highest risk tool.** No commands execute without an explicit whitelist.  
**Security:** Mandatory command whitelist, metacharacter blocking, timeout, output size cap.

### AIToolData

4D database access via ORDA.

```4d
var $tool:=cs.AIToolData.new({ \
  allowedDataclasses: ["Product"; "Category"]; \  // Table whitelist
  maxRecords: 50; \
  readOnly: True \
})
```

**Tools:** `list_dataclasses`, `get_dataclass_info`, `query_data`  
**Security:** Dataclass whitelist, record limit, read-only by default, attribute projection.

### AIToolImage

Generate images from text prompts via the OpenAI Images API. Requires an OpenAI client instance.

```4d
var $tool:=cs.AIToolImage.new($client; { \
  defaultModel: "dall-e-3"; \
  allowedSizes: New collection("1024x1024"); \
  outputFolder: Folder("/PACKAGE/images") \
})
```

**Tools:** `generate_image`  
**Security:** Prompt length cap, model/size whitelists, output folder restriction. Note: each call costs API credits.

### AIToolCalculator

Safe math expression evaluation via the [ExpressionLanguage](https://github.com/mesopelagique/ExpressionLanguage) component. A sandboxed alternative to giving the LLM a "run code" tool — no access to 4D commands, file I/O, network, or database.

```4d
var $tool:=cs.AIToolCalculator.new({ \
  maxExpressionLength: 500 \
})
```

**Tools:** `evaluate_expression`  
**Security:** 🟢 Lowest risk tool. Sandboxed expression engine — only registered math functions available (abs, round, sqrt, pow, log, sin/cos/tan, min, max, floor, ceil, pi, e, random). No code execution possible.

## Project Structure

```
4D-AIKit-Tools/
├── Project/
│   ├── 4D AIKit Tools.4DProject
│   └── Sources/
│       ├── Classes/
│       │   ├── AIToolWebFetch.4dm       # Web page fetching
│       │   ├── AIToolSearch.4dm         # DuckDuckGo search
│       │   ├── AIToolFileSystem.4dm     # File operations
│       │   ├── AIToolCommand.4dm        # Shell commands
│       │   ├── AIToolData.4dm           # ORDA database queries
│       │   ├── AIToolImage.4dm          # Image generation
│       │   └── AIToolCalculator.4dm     # Math expressions
│       ├── Methods/
│       │   ├── TestOpenAI.4dm           # API key helper
│       │   ├── test_web_fetch.4dm       # WebFetch test
│       │   ├── test_search.4dm          # Search test
│       │   ├── test_filesystem.4dm      # FileSystem test
│       │   ├── test_command.4dm         # Command test
│       │   ├── test_data.4dm            # Data test
│       │   ├── test_image.4dm            # Image test
│       │   ├── test_calculator.4dm       # Calculator test
│       │   └── demo_agent.4dm           # Multi-tool demo
│       └── dependencies.json
├── Documentation/
│   ├── tools-security.md                # ⚠️ Security guide
│   └── Classes/
│       ├── AIToolWebFetch.md
│       ├── AIToolSearch.md
│       ├── AIToolFileSystem.md
│       ├── AIToolCommand.md
│       ├── AIToolData.md
│       ├── AIToolImage.md
│       └── AIToolCalculator.md
└── README.md
```

## Python Reference Implementations

The `datapizza-ai-tools` project contains Python reference implementations of similar tools:

| 4D Tool | Python Equivalent |
|---------|-------------------|
| `AIToolWebFetch` | `datapizza.tools.web_fetch.WebFetchTool` |
| `AIToolSearch` | `datapizza.tools.duckduckgo.DuckDuckGoSearchTool` |
| `AIToolFileSystem` | `datapizza.tools.filesystem.FileSystem` |
| `AIToolData` | `datapizza.tools.SQLDatabase.SQLDatabase` |
| `AIToolCommand` | *(no Python equivalent — custom addition)* |

## Documentation

- **[Security Guide](Documentation/tools-security.md)** — Risk analysis and secure configuration for each tool
- **API Reference:**
  - [AIToolWebFetch](Documentation/Classes/AIToolWebFetch.md)
  - [AIToolSearch](Documentation/Classes/AIToolSearch.md)
  - [AIToolFileSystem](Documentation/Classes/AIToolFileSystem.md)
  - [AIToolCommand](Documentation/Classes/AIToolCommand.md)
  - [AIToolData](Documentation/Classes/AIToolData.md)
  - [AIToolImage](Documentation/Classes/AIToolImage.md)
  - [AIToolCalculator](Documentation/Classes/AIToolCalculator.md)

## Roadmap — Future Tools

Ideas for tools that could be added in the future:

| Tool | Description |
|------|-------------|
| **Vector Store Conversational Memory** | Store conversation history in a vector store and retrieve relevant parts of past conversations based on the current input. Enables long-term context recall beyond the token window. |
| **Vector Store Data Retrieval (RAG)** | Look up entities from a dataclass using vector embeddings and semantic similarity — a Retrieval-Augmented Generation pattern. The agent asks a natural language question, and the tool returns the most relevant records. |
| **Planning** | Break a user goal into ordered, executable steps for an autonomous agent. Sends the goal to an LLM client that returns a structured plan the agent can follow step by step. |
| **Calendar** | Read/create/update calendar events via 4D NetKit (Google Calendar, Microsoft Outlook). |
| **Gmail / Outlook Mail** | Extend `AIToolMail` with 4D NetKit OAuth2 providers for Gmail and Microsoft 365, replacing raw SMTP. |
| **Notification** | Send push notifications, Slack messages, or webhook calls to alert users of agent progress. |

> Contributions and ideas welcome — open an issue or PR.

## License

MIT
