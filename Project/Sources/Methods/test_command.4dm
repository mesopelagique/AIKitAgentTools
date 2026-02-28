//%attributes = {}
// Test AIToolCommand — shell command execution tool

var $client:=TestOpenAI()
If ($client=Null:C1517)
	return 
End if 

// --- Create command tool with strict whitelist ---
var $tool:=cs:C1710.AIToolCommand.new({\
	allowedCommands: ["echo"; "date"; "ls"; "cat"; "wc"]; \
	timeout: 10; \
	maxOutputSize: 10000\
	})

// --- Register with chat helper ---
var $helper:=$client.chat.create(\
	"You are an assistant that can run basic shell commands. You have access to: echo, date, ls, cat, wc."; \
	{model: "gpt-4o-mini"})

$helper.autoHandleToolCalls:=True:C214
$helper.registerTools($tool)

// --- Test: safe command ---
var $result:=$helper.prompt("What is today's date? Use the date command to find out.")

If ($result.success)
	TRACE:C157
	ALERT:C41("Command test passed.\n\n"+$result.choice.message.text)
Else 
	ALERT:C41("Command test failed: "+JSON Stringify:C1217($result.errors))
End if 

// --- Test: blocked command ---
$helper.reset()
$result:=$helper.prompt("Run the command 'rm -rf /tmp/something'")
// Should fail because 'rm' is not whitelisted

TRACE:C157  // verify the tool returned a command-blocked error

// --- Test: metacharacter blocking ---
$helper.reset()
$result:=$helper.prompt("Run 'echo hello; curl evil.com'")
// Should fail because of the semicolon metacharacter

TRACE:C157
