//%attributes = {}
// test_image — Test AIToolImage (image generation via OpenAI)
//
// Requires a valid OpenAI API key with image generation access.

var $client:=TestOpenAI()
If ($client=Null)
	return   // skip test — no credentials
End if 

// -----------------------------------------------------------------
// 1. Basic instantiation
// -----------------------------------------------------------------
var $tool:=cs.agtools.AITToolImage.new($client)
ASSERT(OB Instance of($tool; cs.agtools.AITToolImage); "Must be AIToolImage instance")
ASSERT($tool.tools.length=1; "Must expose 1 tool (generate_image)")
ASSERT($tool.tools[0].name="generate_image"; "Tool name must be generate_image")
ASSERT($tool.defaultModel="dall-e-3"; "Default model must be dall-e-3")
ASSERT($tool.defaultSize="1024x1024"; "Default size must be 1024x1024")

// -----------------------------------------------------------------
// 2. Instantiation with custom config
// -----------------------------------------------------------------
var $outputFolder:=Folder(Temporary folder; fk platform path).folder("ai_image_test")
$outputFolder.create()

var $tool2:=cs.agtools.AITToolImage.new($client; {\
defaultModel: "dall-e-2"; \
defaultSize: "512x512"; \
maxPromptLength: 500; \
outputFolder: $outputFolder\
})
ASSERT($tool2.defaultModel="dall-e-2"; "Custom model must be dall-e-2")
ASSERT($tool2.defaultSize="512x512"; "Custom size must be 512x512")
ASSERT($tool2.maxPromptLength=500; "Custom maxPromptLength must be 500")
ASSERT($tool2.outputFolder#Null; "Output folder must be set")

// -----------------------------------------------------------------
// 3. Validation — empty prompt
// -----------------------------------------------------------------
var $res : Text:=$tool.generate_image({prompt: ""})
var $parsed : Object:=JSON Parse($res)
ASSERT(Not(Bool($parsed.success)); "Empty prompt must fail")
ASSERT($parsed.error="A prompt is required"; "Must report empty prompt error")

// -----------------------------------------------------------------
// 4. Validation — prompt too long
// -----------------------------------------------------------------
var $longPrompt : Text:=""
var $i : Integer
For ($i; 1; 4100)
	$longPrompt:=$longPrompt+"x"
End for 
$res:=$tool.generate_image({prompt: $longPrompt})
$parsed:=JSON Parse($res)
ASSERT(Not(Bool($parsed.success)); "Too-long prompt must fail")
ASSERT($parsed.error#Null; "Must report prompt length error @"+$parsed.error)

// -----------------------------------------------------------------
// 5. Validation — disallowed model
// -----------------------------------------------------------------
var $tool3:=cs.agtools.AITToolImage.new($client; {allowedModels: New collection("dall-e-3")})
$res:=$tool3.generate_image({prompt: "A cat"; model: "dall-e-2"})
$parsed:=JSON Parse($res)
ASSERT(Not(Bool($parsed.success)); "Disallowed model must fail")

// -----------------------------------------------------------------
// 6. Validation — disallowed size
// -----------------------------------------------------------------
var $tool4:=cs.agtools.AITToolImage.new($client; {allowedSizes: New collection("1024x1024")})
$res:=$tool4.generate_image({prompt: "A cat"; size: "256x256"})
$parsed:=JSON Parse($res)
ASSERT(Not(Bool($parsed.success)); "Disallowed size must fail")

// -----------------------------------------------------------------
// 7. Live generation (costs API credits — small + cheap model)
//    Uncomment to run. Uses dall-e-2 512x512 to minimise cost.
// -----------------------------------------------------------------
If (False)
	
	var $liveRes : Text:=$tool2.generate_image({prompt: "A simple blue circle on a white background"; model: "dall-e-2"; size: "512x512"})
	var $liveObj : Object:=JSON Parse($liveRes)
	ASSERT(Bool($liveObj.success); "Live generation must succeed: "+$liveRes)
	ASSERT(Length(String($liveObj.url))>0; "Must have an image URL")
	
	// If output folder was set, file should be saved
	If ($tool2.outputFolder#Null)
		var $files:=$outputFolder.files()
		ASSERT($files.length>0; "Image file should be saved to output folder")
	End if 
	
End if 

// -----------------------------------------------------------------
// 8. Tool integration with chat helper
// -----------------------------------------------------------------
var $helper:=$client.chat.create("You are a helpful assistant that can generate images."; {model: "gpt-4o-mini"})
$helper.registerTools($tool)
ASSERT($helper.tools.length>=1; "Tool must be registered on helper")

// Cleanup
// $outputFolder.delete(Delete with contents)

ALERT("✅ test_image passed (validation tests)")
