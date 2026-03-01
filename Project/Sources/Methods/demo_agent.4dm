//%attributes = {}
// demo_agent — Multi-tool agent combining all 7 AI tools
//
// Demonstrates how to register multiple tool providers on a single
// OpenAIChatHelper instance, enabling the LLM to orchestrate across
// web search, page fetching, file system, shell commands, database queries,
// image generation, and math computation.

var $client:=TestOpenAI()
If ($client=Null)
	return 
End if 

// -----------------------------------------------------------------
// 1. Configure each tool with appropriate security settings
// -----------------------------------------------------------------

// Web fetch — restricted to specific domains
var $webFetch:=cs.agtools.AITToolWebFetch.new({\
allowedDomains: ["*.wikipedia.org"; "httpbin.org"; "*.github.com"]; \
timeout: 15; \
maxResponseSize: 20000\
})

// Search — limit result count
var $search:=cs.agtools.AITToolSearch.new({maxResults: 3})

// File system — sandboxed to a temp directory
var $sandbox:=Folder(Temporary folder; fk platform path).folder("ai_agent_demo")
$sandbox.create()

var $fileSystem:=cs.agtools.AITToolFileSystem.new({\
allowedPaths: [$sandbox.path]; \
readOnly: False; \
deniedPaths: ["*.env"; "*.key"; "*.secret"]\
})

// Command — only safe read-only commands
var $command:=cs.agtools.AITToolCommand.new({\
allowedCommands: ["echo"; "date"; "ls"; "cat"; "wc"; "head"; "tail"]; \
timeout: 10\
})

// Data — read-only access (adjust allowedDataclasses for your database)
var $data:=cs.agtools.AITToolData.new({\
maxRecords: 20; \
readOnly: True\
})

// Image — generate images via OpenAI (saves to temp folder)
var $imageFolder:=Folder(Temporary folder; fk platform path).folder("ai_agent_images")
$imageFolder.create()

var $image:=cs.agtools.AITToolImage.new($client; {\
defaultModel: "dall-e-3"; \
allowedSizes: New collection("512x512"; "1024x1024"); \
maxPromptLength: 2000; \
outputFolder: $imageFolder\
})

// Calculator — safe math expressions (sandboxed, no code execution)
var $calculator:=cs.agtools.AITToolCalculator.new()

// Memory — in-memory key-value store for agent context
var $memory:=cs.agtools.AITToolMemory.new({maxEntries: 100; maxValueLength: 5000})

// Mail — SMTP email (disabled by default — uncomment and configure to enable)
// var $smtpServer:={host: "smtp.example.com"; port: 587; user: "bot@example.com"; password: "your-password"}
// var $mail:=cs.agtools.AITToolMail.new($smtpServer; {\
//   fromAddress: "bot@example.com"; \
//   fromName: "AI Assistant"; \
//   allowedRecipientDomains: New collection("example.com"); \
//   maxRecipients: 3\
// })

// -----------------------------------------------------------------
// 2. Create a chat helper and register all tools
// -----------------------------------------------------------------

var $system : Text:="You are a powerful research assistant with access to multiple tools:\n"
$system:=$system+"- **duckduckgo_search**: Search the web for information\n"
$system:=$system+"- **web_fetch**: Fetch and read web page content\n"
$system:=$system+"- **list_directory/read_file/write_file**: Manage files in: "+$sandbox.path+"\n"
$system:=$system+"- **run_command**: Execute shell commands (echo, date, ls, cat, wc, head, tail)\n"
$system:=$system+"- **list_dataclasses/get_dataclass_info/query_data**: Query the 4D database\n\n"
$system:=$system+"- **generate_image**: Generate images from text descriptions\n\n"
$system:=$system+"- **evaluate_expression**: Evaluate math expressions safely (sqrt, pow, min, max, round, sin, cos, pi, etc.)\n\n"
$system:=$system+"- **memory_store/memory_retrieve/memory_list/memory_delete**: Remember and recall facts, preferences, and context\n\n"
$system:=$system+"- **send_email/check_email_connection**: Send emails via SMTP (if configured)\n\n"
$system:=$system+"Combine tools as needed. For example, search for info, fetch a page, and save a summary to a file."

var $helper:=$client.chat.create($system; {model: "gpt-4o-mini"})
$helper.autoHandleToolCalls:=True

// Register all tool providers
$helper.registerTools($webFetch)
$helper.registerTools($search)
$helper.registerTools($fileSystem)
$helper.registerTools($command)
$helper.registerTools($data)
$helper.registerTools($image)
$helper.registerTools($calculator)
$helper.registerTools($memory)
// $helper.registerTools($mail)  // Uncomment when SMTP is configured

// -----------------------------------------------------------------
// 3. Run a multi-tool task
// -----------------------------------------------------------------

var $result:=$helper.prompt(\
"Search for '4D programming language', fetch the Wikipedia page about it if there is one, "+\
"then write a brief summary (3-4 sentences) to a file called 'summary.md' in the sandbox directory. "+\
"Also tell me what today's date is using the date command.")

If ($result.success)
	ALERT("✅ Demo agent completed successfully!\n\n"+$result.choice.message.text)
	
	// Show the conversation flow
	TRACE  // inspect $helper.messages to see the full tool call chain
	
Else 
	ALERT("❌ Demo agent failed: "+JSON Stringify($result.errors))
End if 

// -----------------------------------------------------------------
// 4. Show what was saved
// -----------------------------------------------------------------
var $summaryFile:=$sandbox.file("summary.md")
If ($summaryFile.exists)
	ALERT("📄 Saved summary:\n\n"+$summaryFile.getText())
End if 

// Cleanup
// $sandbox.delete(Delete with contents)  // uncomment to auto-clean
