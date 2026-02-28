//%attributes = {}
// Test AIToolSearch — DuckDuckGo search tool

var $client:=TestOpenAI()
If ($client=Null:C1517)
	return 
End if 

// --- Create search tool ---
var $tool:=cs:C1710.AIToolSearch.new({maxResults: 3; timeout: 15})

// --- Register with chat helper ---
var $helper:=$client.chat.create(\
	"You are an assistant that can search the web. Use the search tool to answer questions about current events or topics you don't know about."; \
	{model: "gpt-4o-mini"})

$helper.autoHandleToolCalls:=True:C214
$helper.registerTools($tool)

// --- Test: simple search ---
var $result:=$helper.prompt("Search for '4D programming language' and summarize what you find.")

If ($result.success)
	TRACE:C157
	ALERT:C41("Search test passed.\n\n"+$result.choice.message.text)
Else 
	ALERT:C41("Search test failed: "+JSON Stringify:C1217($result.errors))
End if 
