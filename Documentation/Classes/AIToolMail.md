# AIToolMail

The `AIToolMail` class provides an email sending tool that uses a pre-configured `4D.SMTPTransporter` to send emails. It's designed for agents that need to send notifications, reports, or messages on behalf of the user.

> **⚠️ Security:** An LLM with email access can send spam, exfiltrate data, or impersonate users. Always configure `allowedRecipientDomains` and lock the `fromAddress`. See [Security Guide](../tools-security.md).

> **Future:** This tool currently supports SMTP. A future version may add 4D NetKit providers for Gmail (Google) and Outlook (Microsoft) via OAuth2.

## Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `fromAddress` | Text | *(empty)* | Locked sender address. The LLM cannot change this. |
| `fromName` | Text | *(empty)* | Display name for the sender (e.g. `"Support Bot"`). |
| `allowedRecipientDomains` | Collection | `[]` (all) | Domain whitelist for recipients. E.g. `["example.com"; "partner.org"]`. Supports wildcards: `"*.example.com"`. **Empty = all domains (⚠️ risky).** |
| `maxRecipients` | Integer | `5` | Maximum total recipients (to + cc + bcc combined). |
| `maxSubjectLength` | Integer | `500` | Maximum subject line length. |
| `maxBodyLength` | Integer | `50000` | Maximum body length (~50KB) for both text and HTML. |

## Constructor

The constructor accepts either a `4D.SMTPTransporter` instance or a server configuration object as the first argument, and an optional security/config object as the second.

```4d
// Option A: Pass a pre-built transporter
var $server:={host: "smtp.gmail.com"; port: 465; user: "bot@company.com"; password: "app-password"}
var $transporter:=SMTP New transporter($server)
var $mail:=cs.agtools.AITToolMail.new($transporter; { \
  fromAddress: "bot@company.com"; \
  fromName: "Assistant Bot"; \
  allowedRecipientDomains: ["company.com"; "partner.org"]; \
  maxRecipients: 3 \
})
```

```4d
// Option B: Pass server config directly (transporter created internally)
var $mail:=cs.agtools.AITToolMail.new( \
  {host: "smtp.company.com"; port: 587; user: "bot@company.com"; password: "xxx"}; \
  { \
    fromAddress: "bot@company.com"; \
    allowedRecipientDomains: ["company.com"] \
  } \
)
```

## Tool Functions

### `send_email()`

Send an email via the configured SMTP transporter.

| Parameter | Type | Description |
|-----------|------|-------------|
| *params.to* | Text | Recipient address(es), comma-separated. E.g. `"alice@example.com"` or `"alice@example.com,bob@example.com"`. |
| *params.subject* | Text | Email subject line. |
| *params.body* | Text | Plain text email body. |
| *params.htmlBody* | Text | Optional HTML body. When provided, both plain text and HTML are sent (multipart/alternative). |
| *params.cc* | Text | Optional CC recipient(s), comma-separated. |
| *params.bcc* | Text | Optional BCC recipient(s), comma-separated. |
| *params.replyTo* | Text | Optional reply-to address. |
| Result | Text | Success confirmation or error message. |

**Security checks performed:**
1. Required field validation (to, subject, body)
2. Subject/body length enforcement
3. Total recipient count check (to + cc + bcc ≤ `maxRecipients`)
4. Recipient domain whitelist validation (all recipients checked)
5. From address locked to configuration (LLM cannot override)

Supports address formats: `"user@domain.com"` and `"Display Name <user@domain.com>"`.

### `check_email_connection()`

Test the SMTP server connection without sending anything.

| Parameter | Type | Description |
|-----------|------|-------------|
| Result | Text | Connection status message. |

## Example — Email Notification Agent

```4d
var $client:=cs.AIKit.OpenAI.new()

var $transporter:=SMTP New transporter({ \
  host: "smtp.company.com"; \
  port: 587; \
  user: "assistant@company.com"; \
  password: $smtpPassword \
})

var $mail:=cs.agtools.AITToolMail.new($transporter; { \
  fromAddress: "assistant@company.com"; \
  fromName: "AI Assistant"; \
  allowedRecipientDomains: ["company.com"]; \
  maxRecipients: 5 \
})

var $helper:=$client.chat.create( \
  "You are an office assistant. You can send emails to company employees. " + \
  "Always confirm with the user before sending an email."; \
  {model: "gpt-4o"})
$helper.autoHandleToolCalls:=True
$helper.registerTools($mail)

$helper.prompt("Send a meeting reminder to alice@company.com about tomorrow's standup at 9 AM")
```

## Example — Combined with Other Tools

```4d
// Agent that can search the web and email a summary
var $mail:=cs.agtools.AITToolMail.new($transporter; { \
  fromAddress: "bot@company.com"; \
  allowedRecipientDomains: ["company.com"] \
})
var $search:=cs.agtools.AITToolSearch.new({maxResults: 5})
var $webFetch:=cs.agtools.AITToolWebFetch.new({allowedDomains: ["*.wikipedia.org"]})

$helper.registerTools($mail)
$helper.registerTools($search)
$helper.registerTools($webFetch)

$helper.prompt("Search for the latest 4D v21 features, summarize them, and email the summary to dev-team@company.com")
```
