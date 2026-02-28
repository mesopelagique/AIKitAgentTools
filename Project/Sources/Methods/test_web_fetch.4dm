//%attributes = {}
// Test AIToolWebFetch — web page fetching tool

var $client:=TestOpenAI()
If ($client=Null:C1517)
	return 
End if 

// --- Create tool with domain restriction ---
var $tool:=cs:C1710.AIToolWebFetch.new({\
	allowedDomains: ["*.wikipedia.org"; "httpbin.org"; "api.github.com"]; \
	timeout: 15; \
	maxResponseSize: 10000\
	})

// --- Register with chat helper ---
var $helper:=$client.chat.create(\
	"You are an assistant that can fetch web pages. When asked to fetch a page, use the web_fetch tool. Summarize the page content briefly."; \
	{model: "gpt-4o-mini"})

$helper.autoHandleToolCalls:=True:C214
$helper.registerTools($tool)

// --- Test: fetch a page ---
var $result:=$helper.prompt("Fetch the content of https://httpbin.org/html and tell me what it says.")

If ($result.success)
	TRACE:C157  // inspect $result.choice.message.text
	ALERT:C41("WebFetch test passed.\n\n"+$result.choice.message.text)
Else 
	ALERT:C41("WebFetch test failed: "+JSON Stringify:C1217($result.errors))
End if 

// --- Test: blocked domain ---
$helper.reset()
$result:=$helper.prompt("Fetch the content of https://evil.example.com/steal-data")

TRACE:C157  // verify the tool returned a domain-blocked error

// -----------------------------------------------------------------
// Test REST methods (POST, etc.)
// -----------------------------------------------------------------

// Tool with only GET allowed (default) — POST should be blocked
var $getOnlyTool:=cs:C1710.AIToolWebFetch.new({\
	allowedDomains: ["httpbin.org"]; \
	timeout: 15\
	})

var $res : Text:=$getOnlyTool.web_fetch({url: "https://httpbin.org/post"; method: "POST"; body: "{\"test\":1}"})
ASSERT:C1129(Position:C15("not allowed"; $res)>0; "POST must be blocked when only GET is allowed: "+$res)

// Tool with GET + POST allowed
var $restTool:=cs:C1710.AIToolWebFetch.new({\
	allowedDomains: ["httpbin.org"]; \
	allowedMethods: New collection:C1472("GET"; "POST"); \
	timeout: 15; \
	maxResponseSize: 10000\
	})

// Test POST to httpbin
var $postHeaders : Object:=New object:C1471
$postHeaders["Content-Type"]:="application/json"
$res:=$restTool.web_fetch({url: "https://httpbin.org/post"; method: "POST"; body: "{\"hello\":\"world\"}"; headers: $postHeaders})
ASSERT:C1129(Position:C15("hello"; $res)>0; "POST response must echo our body: "+Substring:C12($res; 1; 200))

// Test that DELETE is still blocked
$res:=$restTool.web_fetch({url: "https://httpbin.org/delete"; method: "DELETE"})
ASSERT:C1129(Position:C15("not allowed"; $res)>0; "DELETE must be blocked when only GET+POST allowed: "+$res)

// Test GET still works
$res:=$restTool.web_fetch({url: "https://httpbin.org/get"})
ASSERT:C1129(Position:C15("httpbin.org"; $res)>0; "GET must still work: "+Substring:C12($res; 1; 200))

ALERT:C41("✅ test_web_fetch REST methods passed")
