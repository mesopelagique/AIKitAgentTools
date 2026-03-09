# AIToolCommand

The `AIToolCommand` class provides shell command execution with two backends:

- `4D.SystemWorker`
- `PTY4D` plugin (when present)

It enforces a **mandatory command whitelist** — no commands can be executed unless explicitly allowed.

> **🔴 CRITICAL SECURITY:** This is the **highest-risk tool**. Shell command execution enables arbitrary code execution, data exfiltration, and privilege escalation. **Never** use an empty whitelist or disable metacharacter blocking in production. See [Security Guide](../tools-security.md).

## Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `tools` | Collection | *auto* | Tool definitions for registration with `registerTools()`. |
| `allowedCommands` | Collection | `[]` (none) | **Mandatory** whitelist of allowed command names. Empty = all commands blocked. |
| `workingDirectory` | Text | `""` | Working directory for command execution. Empty = 4D default. |
| `timeout` | Integer | `30` | Command execution timeout in seconds. |
| `maxOutputSize` | Integer | `50000` | Maximum output size in characters. Truncated beyond this. |
| `blockMetacharacters` | Boolean | `True` | Block dangerous shell metacharacters (`\|`, `;`, `&&`, `` ` ``, `$(`, etc.). |
| `executionBackend` | Text | `"auto"` | Backend selection: `auto`, `pty`, or `systemworker`. |
| `forceSystemWorker` | Boolean | `False` | Force `4D.SystemWorker` even if PTY plugin is available. |
| `ptyAvailable` | Boolean | *auto-detected* | `True` when a PTY plugin is detected via `PLUGIN LIST`. |
| `ptyPluginName` | Text | `""` | Detected PTY plugin name (if any). |
| `ptyShell` | Text | `"/bin/zsh"` | Shell used by PTY backend. |
| `ptyCols` / `ptyRows` | Integer | `120` / `30` | PTY terminal size for command execution. |
| `ptyReadBufferSize` | Integer | `65536` | PTY read buffer size. |
| `ptyReadTimeoutMs` | Integer | `200` | PTY read timeout in milliseconds. |

## Constructor

### new()

**new**(*config* : Object) : AIToolCommand

| Parameter | Type | Description |
|-----------|------|-------------|
| *config* | Object | Configuration object. **`allowedCommands` is required for the tool to function.** |
| Result | AIToolCommand | New instance. |

#### Example

```4d
// Allow only safe read-only commands
var $tool:=cs.agtools.AIToolCommand.new({ \
  allowedCommands: ["echo"; "date"; "ls"; "cat"; "wc"; "head"; "tail"]; \
  executionBackend: "auto"; \
  forceSystemWorker: False; \
  timeout: 10 \
})
```

## Tool Functions

### run_command()

**run_command**(*params* : Object) : Text

| Parameter | Type | Description |
|-----------|------|-------------|
| *params.command* | Text | Full command string to execute (e.g. `"ls -la /tmp"`). |
| *params.backend* | Text | Optional per-call backend override: `auto`, `pty`, `systemworker`. |
| Result | Text | Command stdout (and stderr if present), or error message. |

Executes a shell command after validating it against the whitelist and checking for dangerous metacharacters. In `auto` mode, PTY is used when available, otherwise `SystemWorker` is used.

**Security checks performed:**
1. Whitelist validation — only the first token (command name) must be in `allowedCommands`
2. Metacharacter blocking — rejects commands containing `|`, `;`, `&&`, `||`, `` ` ``, `$(`, `>`, `>>`, `<<`, `#{`
3. Timeout enforcement
4. Output size truncation
5. Backend fallback safety (`pty` request falls back to `systemworker` if PTY plugin is not available)

**Blocked metacharacters** (when `blockMetacharacters` is `True`):

| Character | Threat |
|-----------|--------|
| `\|` | Pipe to another command |
| `;` | Command chaining |
| `&&` / `\|\|` | Conditional chaining |
| `` ` `` / `$(` | Command substitution |
| `>` / `>>` | Output redirection |
| `<<` | Here-document |
| `#{` | Shell interpolation |

#### Example

```4d
var $tool:=cs.agtools.AIToolCommand.new({ \
  allowedCommands: ["echo"; "date"; "ls"] \
})

var $helper:=$client.chat.create("You can run: echo, date, ls."; {model: "gpt-4o-mini"})
$helper.autoHandleToolCalls:=True
$helper.registerTools($tool)

var $result:=$helper.prompt("What is today's date?")
```

## See Also

- [AIToolFileSystem](AIToolFileSystem.md) — File operations (safer alternative for file access)
- [Security Guide](../tools-security.md) — Detailed security documentation
