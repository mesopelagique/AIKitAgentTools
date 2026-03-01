# AIToolWebFetch

The `AIToolWebFetch` class provides an HTTP fetching tool that uses `4D.HTTPRequest` to retrieve content from URLs. It supports REST API interaction with configurable HTTP methods (GET, POST, PUT, PATCH, DELETE, HEAD).

> **⚠️ Security:** Fetched web content is untrusted and may contain **prompt injection** attacks — adversarial text designed to manipulate the LLM. Always configure `allowedDomains` to restrict access. See [Security Guide](../tools-security.md).

## Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `tools` | Collection | *auto* | Tool definitions for registration with `registerTools()`. |
| `allowedDomains` | Collection | `[]` (all) | Domain whitelist patterns. Supports wildcards: `"*.example.com"`. **Empty = all domains allowed (risky).** |
| `allowedMethods` | Collection | `["GET"]` | Allowed HTTP methods. Only GET by default. Add `"POST"`, `"PUT"`, `"PATCH"`, `"DELETE"`, `"HEAD"` as needed. |
| `timeout` | Integer | `10` | HTTP request timeout in seconds. |
| `userAgent` | Text | `"4D-AIKit-Tools/1.0"` | User-Agent header sent with requests. |
| `maxResponseSize` | Integer | `100000` | Maximum response size in characters. Content is truncated beyond this. |
| `allowedContentTypes` | Collection | `["text/*", "application/json", "application/xml"]` | Allowed response MIME types. Blocks binary downloads by default. |

## Constructor

### new()

**new**(*config* : Object) : AIToolWebFetch

| Parameter | Type | Description |
|-----------|------|-------------|
| *config* | Object | Configuration object (all properties optional). |
| Result | AIToolWebFetch | New instance. |

Creates a new `AIToolWebFetch` instance.

#### Example

```4d
// Restricted to specific domains (recommended)
var $tool:=cs.agtools.AIToolWebFetch.new({ \
  allowedDomains: ["*.wikipedia.org"; "api.github.com"]; \
  timeout: 15; \
  maxResponseSize: 50000 \
})
```

```4d
// REST API tool with POST support
var $tool:=cs.agtools.AIToolWebFetch.new({ \
  allowedDomains: ["api.example.com"]; \
  allowedMethods: New collection("GET"; "POST"); \
  timeout: 20 \
})
```

## Tool Functions

### web_fetch()

**web_fetch**(*params* : Object) : Text

| Parameter | Type | Description |
|-----------|------|-------------|
| *params.url* | Text | The URL to fetch (must start with `https://` or `http://`). |
| *params.method* | Text | HTTP method: GET, POST, PUT, PATCH, DELETE, HEAD. Default: `GET`. Must be in `allowedMethods`. |
| *params.body* | Text | Request body (for POST, PUT, PATCH). Typically a JSON string. |
| *params.headers* | Object | Additional HTTP headers as key-value pairs. E.g. `{"Authorization": "Bearer token"}`. |
| Result | Text | Response body as text, or an error message. |

Fetches content from a URL via HTTP. Validates the URL scheme, checks domain whitelist, blocks private/internal IPs (SSRF protection), validates the HTTP method against `allowedMethods`, and enforces content-type filtering.

**Security checks performed:**
1. URL scheme validation (`https://` or `http://`)
2. HTTP method whitelist check
3. Domain whitelist matching
4. Private/internal IP blocking (localhost, 127.x, 10.x, 192.168.x, etc.)
5. Content-type filtering (text-based only by default)
6. Response size truncation

#### Example — Simple GET

```4d
var $tool:=cs.agtools.AIToolWebFetch.new({allowedDomains: ["httpbin.org"]})

var $helper:=$client.chat.create("You can fetch web pages."; {model: "gpt-4o-mini"})
$helper.autoHandleToolCalls:=True
$helper.registerTools($tool)

var $result:=$helper.prompt("Fetch https://httpbin.org/html and summarize it.")
```

#### Example — REST API with POST

```4d
var $tool:=cs.agtools.AIToolWebFetch.new({ \
  allowedDomains: ["api.example.com"]; \
  allowedMethods: New collection("GET"; "POST"; "DELETE") \
})

var $helper:=$client.chat.create("You are an API assistant. Use web_fetch to interact with the REST API at api.example.com."; {model: "gpt-4o"})
$helper.autoHandleToolCalls:=True
$helper.registerTools($tool)

var $result:=$helper.prompt("Create a new user with name 'Alice' by POSTing to https://api.example.com/users")
```

#### Example — Direct call with custom headers

```4d
var $tool:=cs.agtools.AIToolWebFetch.new({ \
  allowedDomains: ["api.github.com"]; \
  allowedMethods: New collection("GET") \
})

var $res:=$tool.web_fetch({ \
  url: "https://api.github.com/repos/4d/4D-AIKit"; \
  headers: {"Accept": "application/vnd.github.v3+json"} \
})
```

## See Also

- [AIToolSearch](AIToolSearch.md) — Search the web via DuckDuckGo
- [Security Guide](../tools-security.md) — Detailed security documentation
