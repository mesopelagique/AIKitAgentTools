# AIToolData

The `AIToolData` class provides 4D database access via ORDA (Object Relational Data Access). It enables the LLM to explore database structure and query records. Designed for use with [OpenAIChatHelper](https://developer.4d.com/docs/aikit/OpenAIChatHelper) tool registration.

> **⚠️ Security:** Database access can expose sensitive data (PII, credentials, financial records). Always configure `allowedDataclasses` to restrict which tables are accessible, and use `readOnly: True` (the default) to prevent data modification. See [Security Guide](../tools-security.md).

## Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `tools` | Collection | *auto* | Tool definitions for registration with `registerTools()`. |
| `allowedDataclasses` | Collection | `[]` (all) | Whitelist of accessible dataclass names. **Empty = all dataclasses accessible (risky).** |
| `maxRecords` | Integer | `100` | Maximum number of records returned by `query_data`. |
| `readOnly` | Boolean | `True` | Read-only mode (default). Write operations are not exposed. |

## Constructor

### new()

**new**(*config* : Object) : AIToolData

| Parameter | Type | Description |
|-----------|------|-------------|
| *config* | Object | Configuration object (all properties optional). |
| Result | AIToolData | New instance. |

#### Example

```4d
// Restricted to specific dataclasses
var $tool:=cs.AIToolData.new({ \
  allowedDataclasses: ["Product"; "Category"]; \
  maxRecords: 50 \
})
```

## Tool Functions

### list_dataclasses()

**list_dataclasses**(*params* : Object) : Text

| Parameter | Type | Description |
|-----------|------|-------------|
| *params* | Object | No parameters required. |
| Result | Text | Newline-separated list of accessible dataclass names. |

### get_dataclass_info()

**get_dataclass_info**(*params* : Object) : Text

| Parameter | Type | Description |
|-----------|------|-------------|
| *params.dataclass* | Text | Name of the dataclass to inspect. |
| Result | Text | Schema listing with attribute names, types, and kinds. |

### query_data()

**query_data**(*params* : Object) : Text

| Parameter | Type | Description |
|-----------|------|-------------|
| *params.dataclass* | Text | Name of the dataclass to query. |
| *params.query* | Text | ORDA query string (e.g. `"name = \"Smith\""`, `"salary > 50000"`). Leave empty for all records. |
| *params.attributes* | Text | Comma-separated list of attributes to return (e.g. `"name,email"`). Leave empty for all. |
| Result | Text | JSON array of matching records (truncated to `maxRecords`). |

**Security checks performed:**
1. Dataclass whitelist validation
2. Record count limiting (`maxRecords`)
3. Attribute projection to limit exposed columns

#### Example

```4d
var $tool:=cs.AIToolData.new({ \
  allowedDataclasses: ["Employee"; "Department"]; \
  maxRecords: 20 \
})

var $helper:=$client.chat.create( \
  "You are a data analyst. Explore the database to answer questions."; \
  {model: "gpt-4o-mini"})
$helper.autoHandleToolCalls:=True
$helper.registerTools($tool)

var $result:=$helper.prompt("How many employees are there? Show me the first 5.")
```

## See Also

- [AIToolFileSystem](AIToolFileSystem.md) — File-based data access
- [Security Guide](../tools-security.md) — Detailed security documentation
