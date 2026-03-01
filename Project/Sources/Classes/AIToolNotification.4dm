// AIToolNotification - Send notifications to OS notification center or webhook
//
// Default channel is OS notifications via DISPLAY NOTIFICATION(title; text).
// Optional webhook channel can be enabled for integrations (Slack/webhooks/etc.).
//
// Usage:
//   var $tool:=cs.AIToolNotification.new()
//   $helper.registerTools($tool)
//
//   // Optional webhook support
//   var $tool2:=cs.AIToolNotification.new({ \
//     allowedChannels: ["os"; "webhook"]; \
//     webhookURL: "https://hooks.example.com/notify" \
//   })

property tools : Collection
property allowedChannels : Collection
property defaultChannel : Text
property maxTitleLength : Integer
property maxTextLength : Integer
property webhookURL : Text
property webhookTimeout : Integer
property webhookHeaders : Object
property dryRun : Boolean

Class constructor($config : Object)

	If ($config=Null)
		$config:={}
	End if

	// --- Configuration ---
	This.allowedChannels:=New collection()
	var $rawChannels : Collection:=New collection("os")
	If (Value type($config.allowedChannels)=Is collection)
		$rawChannels:=$config.allowedChannels
	End if
	var $channel : Text
	For each ($channel; $rawChannels)
		$channel:=Lowercase(Trim(String($channel)))
		If (Length($channel)>0)
			If (Not(This._isChannelAllowed($channel)))
				This.allowedChannels.push($channel)
			End if
		End if
	End for each

	If (This.allowedChannels.length=0)
		This.allowedChannels.push("os")
	End if

	This.defaultChannel:=($config.defaultChannel#Null) ? Lowercase(Trim(String($config.defaultChannel))) : "os"
	If (Not(This._isChannelAllowed(This.defaultChannel)))
		This.defaultChannel:=String(This.allowedChannels[0])
	End if

	This.maxTitleLength:=($config.maxTitleLength#Null) ? Num($config.maxTitleLength) : 120
	If (This.maxTitleLength<=0)
		This.maxTitleLength:=120
	End if

	This.maxTextLength:=($config.maxTextLength#Null) ? Num($config.maxTextLength) : 1000
	If (This.maxTextLength<=0)
		This.maxTextLength:=1000
	End if

	This.webhookURL:=($config.webhookURL#Null) ? String($config.webhookURL) : ""
	This.webhookTimeout:=($config.webhookTimeout#Null) ? Num($config.webhookTimeout) : 10
	If (This.webhookTimeout<=0)
		This.webhookTimeout:=10
	End if

	This.webhookHeaders:=New object
	If (Value type($config.webhookHeaders)=Is object)
		This.webhookHeaders:=$config.webhookHeaders
	End if
	This.dryRun:=($config.dryRun#Null) ? Bool($config.dryRun) : False

	// --- Tool definition ---
	This.tools:=[]
	This.tools.push({ \
		name: "send_notification"; \
		description: "Send a notification. Default channel is OS notification center. Optional webhook channel can be configured for integrations."; \
		parameters: { \
			type: "object"; \
			properties: { \
				title: {type: "string"; description: "Notification title"}; \
				text: {type: "string"; description: "Notification message text"}; \
				channel: {type: "string"; description: "Notification channel. Allowed: "+This.allowedChannels.join(", "); enum: This.allowedChannels} \
			}; \
			required: ["title"; "text"]; \
			additionalProperties: False \
		} \
	})

Function send_notification($params : Object) : Text

	var $title : Text:=Trim(String($params.title))
	var $text : Text:=Trim(String($params.text))
	var $channel : Text:=($params.channel#Null) ? Lowercase(Trim(String($params.channel))) : This.defaultChannel

	If (Length($title)=0)
		return "Error: 'title' is required."
	End if

	If (Length($text)=0)
		return "Error: 'text' is required."
	End if

	If (Length($title)>This.maxTitleLength)
		return "Error: title exceeds maximum length of "+String(This.maxTitleLength)+" characters."
	End if

	If (Length($text)>This.maxTextLength)
		return "Error: text exceeds maximum length of "+String(This.maxTextLength)+" characters."
	End if

	If (Length($channel)=0)
		$channel:=This.defaultChannel
	End if

	If (Not(This._isChannelAllowed($channel)))
		return "Error: channel '"+$channel+"' is not allowed. Allowed: "+This.allowedChannels.join(", ")
	End if

	Case of
		: ($channel="os")
			return This._sendOSNotification($title; $text)
		: ($channel="webhook")
			return This._sendWebhookNotification($title; $text)
	Else
		return "Error: Unsupported channel '"+$channel+"'."
	End case

Function _sendOSNotification($title : Text; $text : Text) : Text

	If (This.dryRun)
		return "Dry-run: OS notification not displayed. Title: "+$title
	End if

	Try
		DISPLAY NOTIFICATION($title; $text)
		return "OS notification sent successfully."
	Catch
		return "Error: Unable to send OS notification - "+Last errors.last().message
	End try

Function _sendWebhookNotification($title : Text; $text : Text) : Text

	If (Length(This.webhookURL)=0)
		return "Error: webhookURL is not configured."
	End if

	If (This.dryRun)
		return "Dry-run: webhook notification not sent to "+This.webhookURL
	End if

	var $payload : Object:={ \
		title: $title; \
		text: $text; \
		source: "AIToolNotification" \
	}

	var $options : Object:={}
	$options.method:="POST"
	$options.timeout:=This.webhookTimeout
	$options.body:=JSON Stringify($payload)

	var $headers : Object:={}
	$headers["Content-Type"]:="application/json"
	$headers["Accept"]:="application/json, text/plain"
	$headers["User-Agent"]:="4D-AIKit-Tools/1.0"

	// Merge user-provided headers
	var $key : Text
	For each ($key; This.webhookHeaders)
		$headers[$key]:=String(This.webhookHeaders[$key])
	End for each

	$options.headers:=$headers

	Try
		var $request:=4D.HTTPRequest.new(This.webhookURL; $options)
		$request.wait()

		If ($request.response=Null)
			return "Error: Webhook request failed (no response)."
		End if

		var $status : Integer:=$request.response.status
		If (($status<200) || ($status>=300))
			return "Error: Webhook request failed with status "+String($status)+"."
		End if

		return "Webhook notification sent successfully (status "+String($status)+")."
	Catch
		return "Error: Failed to send webhook notification - "+Last errors.last().message
	End try

Function _isChannelAllowed($channel : Text) : Boolean

	var $candidate : Text
	For each ($candidate; This.allowedChannels)
		If (Lowercase(String($candidate))=Lowercase(String($channel)))
			return True
		End if
	End for each
	return False
