# AIToolSearch

The `AIToolSearch` class provides a DuckDuckGo web search tool using `4D.HTTPRequest` to query DuckDuckGo's HTML lite endpoint. It is designed for use with [OpenAIChatHelper](https://developer.4d.com/docs/aikit/OpenAIChatHelper) tool registration.

> **⚠️ Security:** Search results are **untrusted external content**. Adversaries can craft web pages that appear in search results and contain prompt injection text. The LLM may follow malicious instructions embedded in snippets. See [Security Guide](../tools-security.md).

## Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `tools` | Collection | *auto* | Tool definitions for registration with `registerTools()`. |
| `maxResults` | Integer | `5` | Maximum number of search results to return. |
| `timeout` | Integer | `10` | HTTP request timeout in seconds. |

## Constructor

### new()

**new**(*config* : Object) : AIToolSearch

| Parameter | Type | Description |
|-----------|------|-------------|
| *config* | Object | Configuration object (all properties optional). |
| Result | AIToolSearch | New instance. |

Creates a new `AIToolSearch` instance.

#### Example

```4d
var $tool:=cs.agtools.AIToolSearch.new({maxResults: 3; timeout: 15})
```

## Tool Functions

### duckduckgo_search()

**duckduckgo_search**(*params* : Object) : Text

| Parameter | Type | Description |
|-----------|------|-------------|
| *params.query* | Text | The search query. |
| Result | Text | Formatted Markdown list of search results (title, URL, snippet). |

Searches the web using DuckDuckGo. The query is sanitized (HTML tags removed, length capped at 500 characters). Results are parsed from DuckDuckGo's HTML lite endpoint and formatted as a numbered Markdown list.

#### Example

```4d
var $tool:=cs.agtools.AIToolSearch.new({maxResults: 3})

var $helper:=$client.chat.create("You can search the web."; {model: "gpt-4o-mini"})
$helper.autoHandleToolCalls:=True
$helper.registerTools($tool)

var $result:=$helper.prompt("Search for '4D programming language' and summarize what you find.")
```

## See Also

- [AIToolWebFetch](AIToolWebFetch.md) — Fetch full page content after searching
- [Security Guide](../tools-security.md) — Detailed security documentation
