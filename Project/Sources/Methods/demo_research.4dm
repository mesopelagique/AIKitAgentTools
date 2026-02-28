//%attributes = {}
// demo_research — Research agent with web fetch + search
//
// Demonstrates a focused agent with just two tools (web fetch and search)
// that can find information by searching the web and reading pages.
//
// This demo asks about the ORDA equivalent of SET EXTERNAL DATA PATH,
// then follows up to find a blog post about it.

var $client:=TestOpenAI()
If ($client=Null)
	return 
End if 

// -----------------------------------------------------------------
// 1. Configure tools — search + web fetch only
// -----------------------------------------------------------------

var $search:=cs.AIToolSearch.new({maxResults: 5})

var $webFetch:=cs.AIToolWebFetch.new({\
	allowedDomains: ["*.4d.com"; "developer.4d.com"; "blog.4d.com"; "discuss.4d.com"]; \
	timeout: 15; \
	maxResponseSize: 30000\
	})

// -----------------------------------------------------------------
// 2. Create the research assistant
// -----------------------------------------------------------------

var $system : Text:="You are a 4D developer research assistant.\n"
$system+="You have access to two tools:\n"
$system+="- **duckduckgo_search**: Search the web for information\n"
$system+="- **web_fetch**: Fetch and read web page content (restricted to *.4d.com domains)\n\n"
$system+="When researching, first search for relevant pages, then fetch promising URLs to get detailed information.\n"
$system+="Always cite your sources with URLs."

var $helper:=$client.chat.create($system; {model: "gpt-4o-mini"})
$helper.autoHandleToolCalls:=True

$helper.registerTools($search)
$helper.registerTools($webFetch)

// -----------------------------------------------------------------
// 3. First prompt — ask about ORDA equivalent
// -----------------------------------------------------------------

TRACE

var $result:=$helper.prompt(\
	"Is there an ORDA equivalent to the command SET EXTERNAL DATA PATH? "+\
	"I searched the documentation but could not find any.")

If ($result.success)
	ALERT("--- First answer ---\n\n"+$result.choice.message.text)
Else 
	ALERT("❌ First prompt failed: "+JSON Stringify($result.errors))
	return 
End if 

// -----------------------------------------------------------------
// 4. Follow-up — push toward blog.4d.com
// -----------------------------------------------------------------

$result:=$helper.prompt("I am sure there was a post on blog.4d.com about this")

If ($result.success)
	ALERT("--- Follow-up answer ---\n\n"+$result.choice.message.text)
Else 
	ALERT("❌ Follow-up failed: "+JSON Stringify($result.errors))
End if 
