//%attributes = {}
// test_notification - Test AIToolNotification
// -----------------------------------------------------------------
// 1. Basic instantiation
// -----------------------------------------------------------------
var $tool:=cs.AIToolNotification.new({dryRun: Not(Shift down)})
ASSERT(OB Instance of($tool; cs.AIToolNotification); "Must be AIToolNotification instance")
ASSERT($tool.tools.length=1; "Must expose 1 tool (send_notification)")
ASSERT($tool.tools[0].name="send_notification"; "Tool name must be send_notification")
ASSERT($tool.defaultChannel="os"; "Default channel must be os")

// -----------------------------------------------------------------
// 2. Custom config
// -----------------------------------------------------------------
var $tool2:=cs.AIToolNotification.new({\
allowedChannels: ["os"; "webhook"]; \
defaultChannel: "webhook"; \
maxTitleLength: 10; \
maxTextLength: 20; \
dryRun: Not(Shift down); \
webhookURL: "https://hooks.example.com/notify"\
})
ASSERT($tool2.defaultChannel="webhook"; "Custom defaultChannel must be webhook")
ASSERT($tool2.maxTitleLength=10; "Custom maxTitleLength must be 10")
ASSERT($tool2.maxTextLength=20; "Custom maxTextLength must be 20")

// -----------------------------------------------------------------
// 3. Validation - missing title/text
// -----------------------------------------------------------------
var $res : Text:=$tool.send_notification({title: ""; text: "hello"})
ASSERT(Position("'title' is required"; $res)>0; "Missing title must fail")

$res:=$tool.send_notification({title: "Hello"; text: ""})
ASSERT(Position("'text' is required"; $res)>0; "Missing text must fail")

// -----------------------------------------------------------------
// 4. Validation - max lengths
// -----------------------------------------------------------------
$res:=$tool2.send_notification({title: "Title too long"; text: "ok"})
ASSERT(Position("title exceeds maximum length"; $res)>0; "Too-long title must fail")

$res:=$tool2.send_notification({title: "short"; text: "This message is definitely too long"})
ASSERT(Position("text exceeds maximum length"; $res)>0; "Too-long text must fail")

// -----------------------------------------------------------------
// 5. Channel restrictions
// -----------------------------------------------------------------
$res:=$tool.send_notification({title: "Build"; text: "Done"; channel: "webhook"})
ASSERT(Position("is not allowed"; $res)>0; "Disallowed channel must fail")

// -----------------------------------------------------------------
// 6. Dry-run execution
// -----------------------------------------------------------------
$res:=$tool.send_notification({title: "Build finished"; text: "All tests passed"})
ASSERT(Position("Dry-run: OS notification not displayed"; $res)>0; "Dry-run OS path must succeed")

$res:=$tool2.send_notification({title: "Deploy"; text: "Completed"; channel: "webhook"})
ASSERT(Position("Dry-run: webhook notification not sent"; $res)>0; "Dry-run webhook path must succeed")

// -----------------------------------------------------------------
// 7. Webhook requires URL
// -----------------------------------------------------------------
var $tool3:=cs.AIToolNotification.new({\
allowedChannels: ["webhook"]; \
defaultChannel: "webhook"\
})
$res:=$tool3.send_notification({title: "Ops"; text: "Test"})
ASSERT(Position("webhookURL is not configured"; $res)>0; "Webhook channel without URL must fail")

// -----------------------------------------------------------------
// 8. Optional live webhook samples (disabled)
// -----------------------------------------------------------------
If (False)
	// Generic webhook sample
	var $webhookTool:=cs.AIToolNotification.new({\
		allowedChannels: ["webhook"]; \
		defaultChannel: "webhook"; \
		webhookURL: "https://hooks.example.com/notify"; \
		dryRun: False\
		})
	var $webhookResult : Text:=$webhookTool.send_notification({title: "Webhook Test"; text: "Generic webhook notification from test_notification"})
	TRACE
	
	// Slack incoming webhook sample
	// Note: AIToolNotification sends {title; text; source}. If your Slack app
	// expects a strict payload shape, route through a relay endpoint or adapt
	// the tool payload format.
	var $slackTool:=cs.AIToolNotification.new({\
		allowedChannels: ["webhook"]; \
		defaultChannel: "webhook"; \
		webhookURL: "https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX"; \
		dryRun: False\
		})
	var $slackResult : Text:=$slackTool.send_notification({title: "Slack Test"; text: "Slack webhook notification from test_notification"})
	TRACE
End if 

ALERT("test_notification passed")
