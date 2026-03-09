//%attributes = {}
// test_mail_netkit - Validate Gmail/Outlook provider mode wiring in AIToolMail
//
// This test is network-safe:
// - it does not require valid OAuth credentials
// - it does not send real emails
// - it verifies provider setup and pre-send validation paths

var $gmail:=cs.AIToolMail.new({ \
	provider: "gmail"; \
	oauth2: { \
		name: "google"; \
		permission: "service"; \
		clientId: "dummy-client-id"; \
		clientSecret: "dummy-client-secret"; \
		scope: ["https://mail.google.com/"] \
	}; \
	allowedRecipientDomains: ["example.com"]; \
	approvalConfig: {requireApproval: False} \
})

ASSERT($gmail.provider="gmail"; "Gmail provider must be normalized to 'gmail'.")
var $gmailCheck : Text:=$gmail.check_email_connection({})
ASSERT(Length($gmailCheck)>0; "Gmail connection check must return a status message.")

// Domain validation must still enforce whitelist in provider mode.
var $gmailBlocked : Text:=$gmail.send_email({ \
	to: "user@evil.com"; \
	subject: "Blocked"; \
	body: "This should not pass domain validation." \
})
ASSERT(Position("not in the allowed list"; $gmailBlocked)>0; "Gmail provider must enforce recipient whitelist.")

var $outlook:=cs.AIToolMail.new({ \
	provider: "outlook"; \
	oauth2: { \
		name: "Microsoft"; \
		permission: "service"; \
		clientId: "dummy-client-id"; \
		clientSecret: "dummy-client-secret"; \
		tenant: "common"; \
		scope: "https://graph.microsoft.com/.default" \
	}; \
	allowedRecipientDomains: ["example.com"]; \
	approvalConfig: {requireApproval: False} \
})

ASSERT($outlook.provider="outlook"; "Outlook provider must be normalized to 'outlook'.")
var $outlookCheck : Text:=$outlook.check_email_connection({})
ASSERT(Length($outlookCheck)>0; "Outlook connection check must return a status message.")

var $outlookBlocked : Text:=$outlook.send_email({ \
	to: "user@evil.com"; \
	subject: "Blocked"; \
	body: "This should not pass domain validation." \
})
ASSERT(Position("not in the allowed list"; $outlookBlocked)>0; "Outlook provider must enforce recipient whitelist.")

ALERT("test_mail_netkit passed")
