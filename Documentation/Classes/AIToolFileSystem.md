# AIToolFileSystem

The `AIToolFileSystem` class provides file and folder operations using `4D.File` and `4D.Folder`. It includes a sandboxing mechanism via `allowedPaths` / `deniedPaths` to restrict which paths the LLM can access. Designed for use with [OpenAIChatHelper](https://developer.4d.com/docs/aikit/OpenAIChatHelper) tool registration.

> **⚠️ Security:** File system access is **critical risk**. Always configure `allowedPaths` to sandbox the tool. Without it, the LLM can read credentials, overwrite code, or delete files. Enable `readOnly` mode when writes are not needed. See [Security Guide](../tools-security.md).

## Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `tools` | Collection | *auto* | Tool definitions (adjusted based on `readOnly` mode). |
| `allowedPaths` | Collection | `[]` (all) | Allowed root paths. Only files/folders under these paths are accessible. **Empty = unrestricted (dangerous).** |
| `deniedPaths` | Collection | `["*.env", "*.pem", "*.key", "*.secret", "*/.git/*", "*/node_modules/*"]` | Denied path patterns (4D `@` matching). Applied even within allowed paths. |
| `readOnly` | Boolean | `False` | When `True`, only `list_directory` and `read_file` tools are registered. All write operations are disabled. |
| `maxFileSize` | Integer | `500000` | Maximum file size (bytes) that `read_file` will return. Prevents reading huge files. |

## Constructor

### new()

**new**(*config* : Object) : AIToolFileSystem

| Parameter | Type | Description |
|-----------|------|-------------|
| *config* | Object | Configuration object (all properties optional). |
| Result | AIToolFileSystem | New instance. |

#### Example

```4d
// Sandboxed read-write access
var $tool:=cs.agtools.AIToolFileSystem.new({ \
  allowedPaths: ["/Users/me/project/output/"]; \
  readOnly: False \
})

// Read-only access to a project
var $readOnly:=cs.agtools.AIToolFileSystem.new({ \
  allowedPaths: ["/Users/me/project/"]; \
  readOnly: True \
})
```

## Tool Functions

### list_directory()

**list_directory**(*params* : Object) : Text

| Parameter | Type | Description |
|-----------|------|-------------|
| *params.path* | Text | Absolute path of the directory to list. |
| Result | Text | Entries in `[DIR] name` / `[FILE] name` format, one per line. |

### read_file()

**read_file**(*params* : Object) : Text

| Parameter | Type | Description |
|-----------|------|-------------|
| *params.file_path* | Text | Absolute path of the file to read. |
| Result | Text | File content as UTF-8 text, or error message. |

### write_file()

**write_file**(*params* : Object) : Text *(not available in readOnly mode)*

| Parameter | Type | Description |
|-----------|------|-------------|
| *params.file_path* | Text | Absolute path of the file to write. |
| *params.content* | Text | Text content to write. |
| Result | Text | Success or error message. |

### create_directory()

**create_directory**(*params* : Object) : Text *(not available in readOnly mode)*

| Parameter | Type | Description |
|-----------|------|-------------|
| *params.path* | Text | Absolute path of the directory to create. |
| Result | Text | Success or error message. |

### delete_file()

**delete_file**(*params* : Object) : Text *(not available in readOnly mode)*

| Parameter | Type | Description |
|-----------|------|-------------|
| *params.file_path* | Text | Absolute path of the file to delete. |
| Result | Text | Success or error message. |

### move_item()

**move_item**(*params* : Object) : Text *(not available in readOnly mode)*

| Parameter | Type | Description |
|-----------|------|-------------|
| *params.source_path* | Text | Current path of the file or folder. |
| *params.destination_path* | Text | New path. |
| Result | Text | Success or error message. |

### copy_file()

**copy_file**(*params* : Object) : Text *(not available in readOnly mode)*

| Parameter | Type | Description |
|-----------|------|-------------|
| *params.source_path* | Text | Path of the file to copy. |
| *params.destination_path* | Text | Destination path. |
| Result | Text | Success or error message. |

**Security checks performed on every operation:**
1. Path traversal blocking (`..` sequences rejected)
2. Denied path pattern matching (`*.env`, `*.key`, `.git/`, etc.)
3. Allowed path prefix matching (sandbox check)
4. File size limit on reads

#### Example

```4d
var $tool:=cs.agtools.AIToolFileSystem.new({ \
  allowedPaths: ["/tmp/sandbox/"]; \
  readOnly: False \
})

var $helper:=$client.chat.create( \
  "You can manage files in /tmp/sandbox/."; {model: "gpt-4o-mini"})
$helper.autoHandleToolCalls:=True
$helper.registerTools($tool)

var $result:=$helper.prompt("Create a file called notes.txt with 'Hello World', then list the directory.")
```

## See Also

- [AIToolCommand](AIToolCommand.md) — Execute shell commands
- [Security Guide](../tools-security.md) — Detailed security documentation
