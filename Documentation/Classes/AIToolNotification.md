# AIToolNotification

The `AIToolNotification` class sends short notifications from an agent.

- `os` channel: uses `DISPLAY NOTIFICATION(title; text)` for local OS notifications.
- `webhook` channel: optional HTTP POST for integrations (Slack/webhooks/automation endpoints).

> Security note: notifications can be abused for spam/noise or social engineering. Keep message limits low and enable only the channels you need. See [Security Guide](../tools-security.md).

## Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `tools` | Collection | *auto* | Tool definitions for registration with `registerTools()`. |
| `allowedChannels` | Collection | `["os"]` | Allowed channels (`"os"`, `"webhook"`). |
| `defaultChannel` | Text | `"os"` | Channel used when `channel` is omitted. |
| `maxTitleLength` | Integer | `120` | Maximum title length. |
| `maxTextLength` | Integer | `1000` | Maximum message length. |
| `webhookURL` | Text | `""` | Webhook endpoint URL (required for webhook channel). |
| `webhookTimeout` | Integer | `10` | Webhook HTTP timeout (seconds). |
| `webhookHeaders` | Object | `{}` | Optional extra headers for webhook requests. |
| `dryRun` | Boolean | `False` | If `True`, returns success text without sending notifications. |

## Constructor

### new()

**new**(*config* : Object) : AIToolNotification

| Parameter | Type | Description |
|-----------|------|-------------|
| *config* | Object | Optional configuration object. |
| Result | AIToolNotification | New instance. |

```4d
// OS notifications only (default)
var $notify:=cs.agtools.AIToolNotification.new()
```

```4d
// OS + webhook channels
var $notify:=cs.agtools.AIToolNotification.new({ \
  allowedChannels: ["os"; "webhook"]; \
  defaultChannel: "os"; \
  webhookURL: "https://hooks.example.com/notify"; \
  webhookHeaders: {Authorization: "Bearer xxx"} \
})
```

## Tool Functions

### send_notification()

**send_notification**(*params* : Object) : Text

| Parameter | Type | Description |
|-----------|------|-------------|
| *params.title* | Text | Notification title (required). |
| *params.text* | Text | Notification message (required). |
| *params.channel* | Text | Optional channel (`"os"` or `"webhook"` when enabled). |
| Result | Text | Success message or validation/runtime error. |

Behavior:
1. Validates required fields and length limits.
2. Verifies the channel is in `allowedChannels`.
3. Sends via OS notification center or webhook based on channel.

## Example

```4d
var $notify:=cs.agtools.AIToolNotification.new()

var $helper:=$client.chat.create( \
  "You can notify the user when long operations finish."; \
  {model: "gpt-4o-mini"})
$helper.autoHandleToolCalls:=True
$helper.registerTools($notify)

$helper.prompt("Tell me when the report generation is complete.")
```

## Notes for Integrations

- For Slack/Teams/Discord style integrations, use the `webhook` channel with the correct endpoint and headers.
- Keep webhook targets tightly controlled; do not allow arbitrary URLs from model input.

## See Also

- [AIToolMail](AIToolMail.md)
- [Security Guide](../tools-security.md)
