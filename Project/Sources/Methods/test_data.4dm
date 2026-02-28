//%attributes = {}
// Test AIToolData — 4D ORDA data query tool
// Note: This test requires a database with actual dataclasses.
//       Adjust dataclass names to match your database.

var $client:=TestOpenAI()
If ($client=Null:C1517)
	return 
End if 

// --- Create data tool ---
// ⚠️ Adjust allowedDataclasses to match your database tables
var $tool:=cs:C1710.AIToolData.new({\
	maxRecords: 10; \
	readOnly: True:C214\
	})
// To restrict to specific dataclasses:
// var $tool:=cs.AIToolData.new({allowedDataclasses: ["Employee"; "Product"]; maxRecords: 10})

// --- Register with chat helper ---
var $helper:=$client.chat.create(\
	"You are a data analyst assistant. You can explore the database structure and query data. Start by listing available dataclasses if you need to understand the schema."; \
	{model: "gpt-4o-mini"})

$helper.autoHandleToolCalls:=True:C214
$helper.registerTools($tool)

// --- Test: list dataclasses ---
var $result:=$helper.prompt("What dataclasses (tables) are available in this database? List them.")

If ($result.success)
	TRACE:C157
	ALERT:C41("Data tool test passed.\n\n"+$result.choice.message.text)
Else 
	ALERT:C41("Data tool test failed: "+JSON Stringify:C1217($result.errors))
End if 
