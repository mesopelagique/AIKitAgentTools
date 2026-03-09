# AIToolApproval

The `AIToolApproval` class exposes human-in-the-loop approval operations for sensitive tool actions.

It is designed to work with `ApprovalEngine` and supports:

- listing pending requests
- fetching a request by ID
- approving/rejecting requests
- optionally saving reusable allow/deny rules
- listing/deleting rules

## Constructor

```4d
var $approval:=cs.AIToolApproval.new({ \
  approvalConfig: { \
    requireApproval: True; \
    shadowMode: False; \
    requestTTLSeconds: 600 \
  } \
})
```

You can also pass an existing engine:

```4d
var $engine:=cs.ApprovalEngine.new({requireApproval: True})
var $approval:=cs.AIToolApproval.new({approvalEngine: $engine})
```

## Tool Functions

### approval_list_pending()

Returns all requests with `status = "pending"`.

### approval_get_request({requestId})

Returns a single request payload.

### approval_decide({...})

Required:

- `requestId`
- `decision` (`allow` or `deny`)

Optional:

- `saveRule` (boolean)
- `ruleScope` (`session`, `user`, `project`)
- `ttlSeconds`
- `maxUses`
- `matcher` (structured matcher override)
- `decisionReason`
- `decidedBy`

### approval_list_rules({scope, tool, action})

Lists active rules, optionally filtered.

### approval_delete_rule({ruleId})

Disables a rule.

## Structured Matcher

Example matcher used in `approval_decide`:

```json
{
  "tool": "AIToolCommand",
  "action": "run_command",
  "targetType": "command",
  "targetPattern": "git *",
  "argConstraints": {
    "cwdPrefix": "/Users/eric/git"
  }
}
```

## See Also

- [AIToolCommand](AIToolCommand.md)
- [AIToolFileSystem](AIToolFileSystem.md)
- [Security Guide](../tools-security.md)
