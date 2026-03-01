//%attributes = {}
// test_mail — Test AIToolMail (SMTP email sending tool)
//
// NOTE: These tests validate configuration, validation logic, domain checking,
// and tool definitions. Actual sending requires a real SMTP server.

// =================================================================
// 1. Basic instantiation with server config
// =================================================================
// Use a dummy server config — we won't actually connect in these tests
var $serverConfig : Object:={host: "smtp.example.com"; port: 587; user: "bot@example.com"; password: "test123"}
var $tool:=cs.AIToolMail.new($serverConfig; {\
	fromAddress: "bot@example.com"; \
	fromName: "Test Bot"; \
	allowedRecipientDomains: New collection:C1472("example.com"; "partner.org"); \
	maxRecipients: 3\
	})

ASSERT:C1129(OB Instance of:C1731($tool; cs.AIToolMail); "Must be AIToolMail instance")
ASSERT:C1129($tool.tools.length=2; "Must expose 2 tools (send_email, check_email_connection)")
ASSERT:C1129($tool.tools[0].name="send_email"; "Tool 0 = send_email")
ASSERT:C1129($tool.tools[1].name="check_email_connection"; "Tool 1 = check_email_connection")

// =================================================================
// 2. Configuration properties
// =================================================================
ASSERT:C1129($tool.fromAddress="bot@example.com"; "fromAddress must be set")
ASSERT:C1129($tool.fromName="Test Bot"; "fromName must be set")
ASSERT:C1129($tool.maxRecipients=3; "maxRecipients must be 3")
ASSERT:C1129($tool.maxSubjectLength=500; "Default maxSubjectLength = 500")
ASSERT:C1129($tool.maxBodyLength=50000; "Default maxBodyLength = 50000")
ASSERT:C1129($tool.allowedRecipientDomains.length=2; "Must have 2 allowed domains")

// =================================================================
// 3. Default configuration
// =================================================================
var $tool2:=cs.AIToolMail.new($serverConfig)
ASSERT:C1129($tool2.maxRecipients=5; "Default maxRecipients = 5")
ASSERT:C1129($tool2.maxSubjectLength=500; "Default maxSubjectLength = 500")
ASSERT:C1129($tool2.maxBodyLength=50000; "Default maxBodyLength = 50000")
ASSERT:C1129($tool2.allowedRecipientDomains.length=0; "Default: no domain restriction")
ASSERT:C1129(Length:C16($tool2.fromAddress)=0; "Default: no fromAddress")

// =================================================================
// 4. Validation — missing required fields
// =================================================================
var $res : Text

$res:=$tool.send_email({to: ""; subject: "Test"; body: "Hello"})
ASSERT:C1129(Position:C15("Error"; $res)>0; "Empty 'to' must fail: "+$res)

$res:=$tool.send_email({to: "user@example.com"; subject: ""; body: "Hello"})
ASSERT:C1129(Position:C15("Error"; $res)>0; "Empty subject must fail: "+$res)

$res:=$tool.send_email({to: "user@example.com"; subject: "Test"; body: ""})
ASSERT:C1129(Position:C15("Error"; $res)>0; "Empty body must fail: "+$res)

// =================================================================
// 5. Validation — subject too long
// =================================================================
var $longSubject : Text:=""
var $i : Integer
For ($i; 1; 600)
	$longSubject:=$longSubject+"x"
End for 
$res:=$tool.send_email({to: "user@example.com"; subject: $longSubject; body: "Hello"})
ASSERT:C1129(Position:C15("exceeds maximum length"; $res)>0; "Long subject must fail: "+$res)

// =================================================================
// 6. Recipient domain whitelist — blocked domain
// =================================================================
$res:=$tool.send_email({to: "user@evil.com"; subject: "Test"; body: "Hello"})
ASSERT:C1129(Position:C15("not in the allowed list"; $res)>0; "Blocked domain must fail: "+$res)

// =================================================================
// 7. Recipient domain whitelist — allowed domain
// =================================================================
// This will fail at send (no real SMTP server) but should pass validation
$res:=$tool.send_email({to: "user@example.com"; subject: "Test"; body: "Hello"})
// Should NOT show domain error — will show SMTP error instead
ASSERT:C1129(Position:C15("not in the allowed list"; $res)=0; "Allowed domain must pass validation: "+$res)

// =================================================================
// 8. Recipient domain whitelist — partner domain
// =================================================================
$res:=$tool.send_email({to: "user@partner.org"; subject: "Test"; body: "Hello"})
ASSERT:C1129(Position:C15("not in the allowed list"; $res)=0; "partner.org must be allowed: "+$res)

// =================================================================
// 9. Max recipients exceeded
// =================================================================
$res:=$tool.send_email({to: "a@example.com,b@example.com,c@example.com,d@example.com"; subject: "Test"; body: "Hello"})
ASSERT:C1129(Position:C15("too many recipients"; $res)>0; "4 recipients with max 3 must fail: "+$res)

// =================================================================
// 10. Max recipients — including CC and BCC
// =================================================================
$res:=$tool.send_email({to: "a@example.com"; cc: "b@example.com"; bcc: "c@example.com,d@example.com"; subject: "Test"; body: "Hello"})
ASSERT:C1129(Position:C15("too many recipients"; $res)>0; "4 total (to+cc+bcc) with max 3 must fail: "+$res)

// =================================================================
// 11. Invalid email format
// =================================================================
$res:=$tool.send_email({to: "not-an-email"; subject: "Test"; body: "Hello"})
ASSERT:C1129(Position:C15("Error"; $res)>0; "Invalid email must fail: "+$res)

// =================================================================
// 12. Email parsing — angle bracket format
// =================================================================
// "Name <email>" format — domain check should work
$res:=$tool.send_email({to: "Alice <alice@example.com>"; subject: "Test"; body: "Hello"})
ASSERT:C1129(Position:C15("not in the allowed list"; $res)=0; "Angle bracket format must parse correctly: "+$res)

// Evil domain in angle brackets
$res:=$tool.send_email({to: "Alice <alice@evil.com>"; subject: "Test"; body: "Hello"})
ASSERT:C1129(Position:C15("not in the allowed list"; $res)>0; "Evil domain in angle brackets must be caught: "+$res)

// =================================================================
// 13. CC domain validation
// =================================================================
$res:=$tool.send_email({to: "user@example.com"; cc: "spy@evil.com"; subject: "Test"; body: "Hello"})
ASSERT:C1129(Position:C15("not in the allowed list"; $res)>0; "CC to blocked domain must fail: "+$res)

// =================================================================
// 14. Tool parameter definitions
// =================================================================
var $sendDef : Object:=$tool.tools[0]
ASSERT:C1129($sendDef.parameters.required.length=3; "send_email must require 3 params (to, subject, body)")
var $props : Object:=$sendDef.parameters.properties
ASSERT:C1129($props.to#Null; "Must have 'to' param")
ASSERT:C1129($props.subject#Null; "Must have 'subject' param")
ASSERT:C1129($props.body#Null; "Must have 'body' param")
ASSERT:C1129($props.htmlBody#Null; "Must have 'htmlBody' param")
ASSERT:C1129($props.cc#Null; "Must have 'cc' param")
ASSERT:C1129($props.bcc#Null; "Must have 'bcc' param")
ASSERT:C1129($props.replyTo#Null; "Must have 'replyTo' param")

// =================================================================
// 15. No domain restriction (tool2 — open config)
// =================================================================
// tool2 has no allowedRecipientDomains — should pass domain check for any address
$res:=$tool2.send_email({to: "anyone@anywhere.com"; subject: "Test"; body: "Hello"})
ASSERT:C1129(Position:C15("not in the allowed list"; $res)=0; "Open config must allow any domain: "+$res)

ALERT:C41("✅ test_mail — All assertions passed")
