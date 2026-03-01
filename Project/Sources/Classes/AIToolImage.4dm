// AIToolImage — Generate images via the OpenAI Images API
//
// Unlike other AITool* classes, this one requires an OpenAI client instance
// because it delegates to the client's images.generate() method.
//
// Security: prompt length cap, model whitelist, size whitelist, output folder restriction
//
// Usage:
//   var $client:=cs.AIKit.OpenAI.new()
//   var $tool:=cs.agtools.AITToolImage.new($client; {outputFolder: Folder("/PACKAGE/images")})
//   $helper.registerTools($tool)

property tools : Collection
property _client : Object
property allowedModels : Collection
property allowedSizes : Collection
property maxPromptLength : Integer
property outputFolder : Object  // 4D.Folder or Null — when set, images are saved to disk
property defaultModel : Text
property defaultSize : Text
property defaultStyle : Text

Class constructor($client : Object; $config : Object)
	
	If ($config=Null)
		$config:={}
	End if 
	
	// The OpenAI client is mandatory
	This._client:=$client
	
	// --- Configuration ---
	This.defaultModel:=($config.defaultModel#Null) ? $config.defaultModel : "dall-e-3"
	This.defaultSize:=($config.defaultSize#Null) ? $config.defaultSize : "1024x1024"
	This.defaultStyle:=($config.defaultStyle#Null) ? $config.defaultStyle : ""  // empty = API default
	This.maxPromptLength:=($config.maxPromptLength#Null) ? $config.maxPromptLength : 4000
	This.allowedModels:=($config.allowedModels#Null) ? $config.allowedModels : New collection("dall-e-2"; "dall-e-3"; "gpt-image-1")
	This.allowedSizes:=($config.allowedSizes#Null) ? $config.allowedSizes : New collection("256x256"; "512x512"; "1024x1024"; "1024x1792"; "1792x1024")
	This.outputFolder:=($config.outputFolder#Null) ? $config.outputFolder : Null
	
	// Create target folder if provided but missing
	If (This.outputFolder#Null)
		If (Not(This.outputFolder.exists))
			This.outputFolder.create()
		End if 
	End if 
	
	// --- Tool definitions ---
	This.tools:=[]
	
	This.tools.push({\
		name: "generate_image"; \
		description: "Generate an image from a text prompt using an AI image model (DALL-E). Returns the image URL. Use detailed, descriptive prompts for best results."; \
		parameters: {\
		type: "object"; \
		properties: {\
		prompt: {type: "string"; description: "Detailed text description of the image to generate"}; \
		size: {type: "string"; description: "Image dimensions. One of: 256x256, 512x512, 1024x1024, 1024x1792, 1792x1024. Default: 1024x1024"; enum: ["256x256"; "512x512"; "1024x1024"; "1024x1792"; "1792x1024"]}; \
		model: {type: "string"; description: "The model to use. Default: dall-e-3"; enum: ["dall-e-2"; "dall-e-3"; "gpt-image-1"]}; \
		style: {type: "string"; description: "Image style (DALL-E-3 only). 'vivid' for hyper-real/dramatic, 'natural' for more natural, less hyper-real. Default: vivid"; enum: ["vivid"; "natural"]}\
		}; \
		required: ["prompt"]; \
		additionalProperties: False\
		}\
		})
	
	
	// -----------------------------------------------------------------
	// MARK:- Tool handler
	// -----------------------------------------------------------------
Function generate_image($params : Object) : Text
	
	var $prompt : Text:=String($params.prompt)
	
	// --- Validate prompt ---
	If (Length($prompt)=0)
		return JSON Stringify({success: False; error: "A prompt is required"})
	End if 
	
	If (Length($prompt)>This.maxPromptLength)
		return JSON Stringify({success: False; error: "Prompt exceeds maximum length of "+String(This.maxPromptLength)+" characters"})
	End if 
	
	// --- Resolve parameters ---
	var $model : Text:=($params.model#Null) ? String($params.model) : This.defaultModel
	var $size : Text:=($params.size#Null) ? String($params.size) : This.defaultSize
	var $style : Text:=($params.style#Null) ? String($params.style) : This.defaultStyle
	
	// --- Validate model ---
	If (This.allowedModels.length>0)
		If (This.allowedModels.indexOf($model)=-1)
			return JSON Stringify({success: False; error: "Model '"+$model+"' is not allowed. Allowed: "+This.allowedModels.join(", ")})
		End if 
	End if 
	
	// --- Validate size ---
	If (This.allowedSizes.length>0)
		If (This.allowedSizes.indexOf($size)=-1)
			return JSON Stringify({success: False; error: "Size '"+$size+"' is not allowed. Allowed: "+This.allowedSizes.join(", ")})
		End if 
	End if 
	
	// --- Build parameters object ---
	var $imageParams : Object:={model: $model; size: $size}
	If (Length($style)>0)
		$imageParams.style:=$style
	End if 
	$imageParams.response_format:="url"
	
	// --- Call the OpenAI images API ---
	var $result : Object:=This._client.images.generate($prompt; $imageParams)
	
	If (Not(Bool($result.success)))
		return JSON Stringify({success: False; error: "Image generation failed: "+JSON Stringify($result.errors)})
	End if 
	
	If ($result.image=Null)
		return JSON Stringify({success: False; error: "No image returned by the API"})
	End if 
	
	var $imageURL : Text:=String($result.image.url)
	var $revisedPrompt : Text:=String($result.image.revised_prompt)
	
	// --- Optionally save to disk ---
	var $savedPath : Text:=""
	If (This.outputFolder#Null)
		var $timestamp : Text:=String(Timestamp; "yyyy-MM-dd'T'HHmmss")
		var $fileName : Text:="image_"+$timestamp+".png"
		var $targetFile : Object:=This.outputFolder.file($fileName)
		$result.image.saveToDisk($targetFile)
		If ($targetFile.exists)
			$savedPath:=$targetFile.path
		End if 
	End if 
	
	// --- Build response ---
	var $response : Object:={success: True; url: $imageURL; model: $model; size: $size}
	If (Length($revisedPrompt)>0)
		$response.revised_prompt:=$revisedPrompt
	End if 
	If (Length($savedPath)>0)
		$response.saved_to:=$savedPath
	End if 
	
	return JSON Stringify($response)
