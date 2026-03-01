//%attributes = {}
// Test AIToolFileSystem — file system operations tool

var $client:=TestOpenAI()
If ($client=Null)
	return 
End if 

// --- Create a temp sandbox directory ---
var $sandbox:=Folder(Temporary folder; fk platform path).folder("AIToolTest_"+String(Milliseconds))
$sandbox.create()

// --- Create file system tool (sandboxed + read-write) ---
var $tool:=cs.AIToolFileSystem.new({\
allowedPaths: [$sandbox.path]; \
readOnly: False; \
maxFileSize: 100000\
})

// --- Register with chat helper ---
var $helper:=$client.chat.create(\
"You are an assistant that can read and write files. The sandbox directory is: "+$sandbox.path; \
{model: "gpt-4o-mini"})

$helper.autoHandleToolCalls:=True
$helper.registerTools($tool)

// --- Test: create a file, then read it back ---
var $result:=$helper.prompt("Create a file called 'hello.txt' in the sandbox directory with the content 'Hello from AI tool!', then read it back and tell me what it contains.")

If ($result.success)
	// Verify the file was actually created
	var $testFile:=$sandbox.file("hello.txt")
	ASSERT($testFile.exists; "File should have been created by the tool")
	ASSERT($testFile.getText()="Hello from AI tool!"; "File content should match")
	
	TRACE
	ALERT("FileSystem test passed.\n\n"+$result.choice.message.text)
Else 
	ALERT("FileSystem test failed: "+JSON Stringify($result.errors))
End if 

// --- Test: list directory ---
$helper:=$client.chat.create(\
"You are an assistant that can read and write files. The sandbox directory is: "+$sandbox.path; \
{model: "gpt-4o-mini"})

$helper.autoHandleToolCalls:=True
$helper.registerTools($tool)
$result:=$helper.prompt("List the files in the sandbox directory.")

TRACE

// --- Cleanup ---
$sandbox.delete(Delete with contents)
