# AIToolMail

`AIToolMail` sends emails through one of three providers:

- `smtp` (default) via `4D.SMTPTransporter`
- `gmail` via 4D NetKit (`Google.mail.send()`)
- `outlook` via 4D NetKit (`Office365.mail.send()`)

It keeps the same security controls across providers: recipient-domain allowlist, recipient count limits, body/subject limits, locked sender, and optional human approval.

## Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `provider` | Text | `"smtp"` | `smtp`, `gmail`, or `outlook` |
| `fromAddress` | Text | *(empty)* | Locked sender address |
| `fromName` | Text | *(empty)* | Sender display name |
| `allowedRecipientDomains` | Collection | `[]` | Recipient domain allowlist (`[]` = all) |
| `maxRecipients` | Integer | `5` | Max recipients across to+cc+bcc |
| `maxSubjectLength` | Integer | `500` | Subject max length |
| `maxBodyLength` | Integer | `50000` | Text/HTML body max length |
| `netkitMailType` | Text | `"JMAP"` | NetKit mail format (`JMAP`, etc.) |
| `netkitUserId` | Text | *(empty)* | Optional user id for service mode |

## Constructor

### SMTP mode (legacy)

```4d
var $mail:=cs.AIToolMail.new( \
  {host: "smtp.example.com"; port: 587; user: "bot@example.com"; password: "xxx"}; \
  {fromAddress: "bot@example.com"; allowedRecipientDomains: ["example.com"]} \
)
```

Or pass a ready `4D.SMTPTransporter` as the first parameter.

### Gmail mode (NetKit)

```4d
var $mail:=cs.AIToolMail.new({ \
  provider: "gmail"; \
  oauth2: { \
    name: "google"; \
    permission: "signedIn"; \
    clientId: "..."; \
    clientSecret: "..."; \
    redirectURI: "http://127.0.0.1:50993/authorize/"; \
    scope: ["https://mail.google.com/"] \
  }; \
  fromAddress: "bot@example.com"; \
  allowedRecipientDomains: ["example.com"] \
})
```

### Outlook mode (NetKit)

```4d
var $mail:=cs.AIToolMail.new({ \
  provider: "outlook"; \
  oauth2: { \
    name: "Microsoft"; \
    permission: "signedIn"; \
    clientId: "..."; \
    clientSecret: "..."; \
    tenant: "common"; \
    scope: "https://graph.microsoft.com/.default" \
  }; \
  fromAddress: "bot@example.com"; \
  allowedRecipientDomains: ["example.com"] \
})
```

You can also pass a pre-built OAuth2 provider object with `oauth2Provider`.

## Tool Functions

### `send_email(params)`

Required params:

- `to`
- `subject`
- `body`

Optional params:

- `htmlBody`
- `cc`
- `bcc`
- `replyTo`

Returns a success message or an error text.

### `check_email_connection()`

Returns provider readiness info:

- SMTP: live SMTP check using `checkConnection()`
- Gmail/Outlook: NetKit configuration/token readiness message

## Security Notes

- Keep `allowedRecipientDomains` non-empty in production.
- Keep `maxRecipients` low.
- Use `ApprovalEngine` for human confirmation before sends.
- For NetKit providers, request minimal OAuth scopes and protect token storage.

## See Also

- [Security Guide](../tools-security.md)
- [AIToolApproval](AIToolApproval.md)
