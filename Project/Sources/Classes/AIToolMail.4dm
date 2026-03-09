// AIToolMail — Send emails via SMTP, Gmail (Google API), or Outlook (Microsoft Graph)
//
// Security: recipient domain whitelist, max recipients, locked from address,
// subject/body length caps, and optional approval gating.

property tools : Collection
property fromAddress : Text
property fromName : Text
property allowedRecipientDomains : Collection
property maxRecipients : Integer
property maxSubjectLength : Integer
property maxBodyLength : Integer
property provider : Text
property netkitMailType : Text
property netkitUserId : Text
property _transporter : Object
property _approvalEngine : Object
property _netkitOAuth2Provider : Object
property _netkitService : Object
property _netkitInitError : Text

Class constructor($transporterOrConfig : Object; $config : Object)

	// Flexible constructor support:
	// - SMTP (legacy): new(transporterOrServerConfig; config)
	// - NetKit (new):  new({provider: "gmail|outlook"; oauth2: {...}; ...})
	If ($config=Null)
		$config:={}
		If (($transporterOrConfig#Null) & (Value type($transporterOrConfig)=Is object))
			var $firstProvider : Text:=Lowercase(String($transporterOrConfig.provider))
			If (($firstProvider="gmail") | ($firstProvider="google") | ($firstProvider="outlook") | ($firstProvider="office365") | ($firstProvider="microsoft"))
				$config:=$transporterOrConfig
				$transporterOrConfig:=Null
			End if
		End if
	End if

	This.provider:=This._normalizeProvider(($config.provider#Null) ? String($config.provider) : "smtp")
	This.netkitMailType:=($config.netkitMailType#Null) ? String($config.netkitMailType) : "JMAP"
	If (Length(This.netkitMailType)=0)
		This.netkitMailType:="JMAP"
	End if
	This.netkitUserId:=($config.netkitUserId#Null) ? String($config.netkitUserId) : ((($config.userId#Null) ? String($config.userId) : ""))

	// --- Sender and limits ---
	This.fromAddress:=($config.fromAddress#Null) ? String($config.fromAddress) : ""
	This.fromName:=($config.fromName#Null) ? String($config.fromName) : ""
	This.allowedRecipientDomains:=($config.allowedRecipientDomains#Null) ? $config.allowedRecipientDomains : New collection()  // empty = all (risky)
	This.maxRecipients:=($config.maxRecipients#Null) ? Num($config.maxRecipients) : 5
	This.maxSubjectLength:=($config.maxSubjectLength#Null) ? Num($config.maxSubjectLength) : 500
	This.maxBodyLength:=($config.maxBodyLength#Null) ? Num($config.maxBodyLength) : 50000
	If (This.maxRecipients<=0)
		This.maxRecipients:=5
	End if
	If (This.maxSubjectLength<=0)
		This.maxSubjectLength:=500
	End if
	If (This.maxBodyLength<=0)
		This.maxBodyLength:=50000
	End if

	// --- Approval config ---
	If (($config.approvalEngine#Null) & (OB Instance of($config.approvalEngine; cs.ApprovalEngine)))
		This._approvalEngine:=$config.approvalEngine
	Else
		var $approvalConfig : Object:=($config.approvalConfig#Null) ? $config.approvalConfig : {}
		This._approvalEngine:=cs.ApprovalEngine.new($approvalConfig)
	End if

	This._transporter:=Null
	This._netkitOAuth2Provider:=Null
	This._netkitService:=Null
	This._netkitInitError:=""

	// --- Transport/provider initialization ---
	Case of
		: (This.provider="smtp")
			This._initSMTP($transporterOrConfig; $config)
		: ((This.provider="gmail") | (This.provider="outlook"))
			This._initNetKit($config)
	End case

	// --- Tool definitions ---
	This.tools:=[]

	This.tools.push({ \
		name: "send_email"; \
		description: "Send an email via configured provider (smtp, gmail, outlook). Requires to, subject, and body."; \
		parameters: { \
			type: "object"; \
			properties: { \
				to: {type: "string"; description: "Recipient email address(es), comma-separated for multiple."}; \
				subject: {type: "string"; description: "Email subject line"}; \
				body: {type: "string"; description: "Plain text email body"}; \
				htmlBody: {type: "string"; description: "Optional HTML email body"}; \
				cc: {type: "string"; description: "Optional CC recipient(s), comma-separated"}; \
				bcc: {type: "string"; description: "Optional BCC recipient(s), comma-separated"}; \
				replyTo: {type: "string"; description: "Optional reply-to address"} \
			}; \
			required: ["to"; "subject"; "body"]; \
			additionalProperties: False \
		} \
	})

	This.tools.push({ \
		name: "check_email_connection"; \
		description: "Check if the configured email provider is ready."; \
		parameters: {type: "object"; properties: {}; additionalProperties: False} \
	})

	// -----------------------------------------------------------------
	// MARK:- Tool handlers
	// -----------------------------------------------------------------

Function send_email($params : Object) : Text

	var $to : Text:=String($params.to)
	var $subject : Text:=String($params.subject)
	var $body : Text:=String($params.body)
	var $htmlBody : Text:=($params.htmlBody#Null) ? String($params.htmlBody) : ""
	var $cc : Text:=($params.cc#Null) ? String($params.cc) : ""
	var $bcc : Text:=($params.bcc#Null) ? String($params.bcc) : ""
	var $replyTo : Text:=($params.replyTo#Null) ? String($params.replyTo) : ""

	// Required fields
	If (Length($to)=0)
		return "Error: 'to' is required."
	End if
	If (Length($subject)=0)
		return "Error: 'subject' is required."
	End if
	If (Length($body)=0)
		return "Error: 'body' is required."
	End if

	// Length checks
	If (Length($subject)>This.maxSubjectLength)
		return "Error: subject exceeds maximum length of "+String(This.maxSubjectLength)+" characters."
	End if
	If (Length($body)>This.maxBodyLength)
		return "Error: body exceeds maximum length of "+String(This.maxBodyLength)+" characters."
	End if
	If (Length($htmlBody)>This.maxBodyLength)
		return "Error: htmlBody exceeds maximum length of "+String(This.maxBodyLength)+" characters."
	End if

	// Collect/validate recipients
	var $allRecipients : Collection:=[]
	This._parseAddresses($to; $allRecipients)
	If (Length($cc)>0)
		This._parseAddresses($cc; $allRecipients)
	End if
	If (Length($bcc)>0)
		This._parseAddresses($bcc; $allRecipients)
	End if

	If ($allRecipients.length=0)
		return "Error: no valid recipient addresses found."
	End if
	If ($allRecipients.length>This.maxRecipients)
		return "Error: too many recipients ("+String($allRecipients.length)+"). Maximum allowed: "+String(This.maxRecipients)+"."
	End if

	var $domainError : Text:=This._validateRecipientDomains($allRecipients)
	If (Length($domainError)>0)
		return $domainError
	End if

	// Human approval gate
	var $approval : Object:=This._approvalEngine.evaluate({ \
		tool: "AIToolMail"; \
		action: "send_email"; \
		summary: "Send "+This.provider+" email to "+$to+" subject: "+$subject; \
		targetType: "recipient"; \
		targetValue: $to; \
		payload: { \
			provider: This.provider; \
			to: $to; \
			cc: $cc; \
			bcc: $bcc; \
			subject: $subject; \
			bodyLength: Length($body); \
			htmlBodyLength: Length($htmlBody) \
		} \
	})
	If ($approval.status#"allowed")
		return JSON Stringify($approval; *)
	End if

	var $email : Object:=This._buildEmailObject($to; $subject; $body; $htmlBody; $cc; $bcc; $replyTo)
	return This._sendEmailWithProvider($email; $to; $cc; $subject)

Function check_email_connection($params : Object) : Text

	Case of
		: (This.provider="smtp")
			If (This._transporter=Null)
				return "Error: SMTP transporter is not configured."
			End if
			Try
				var $status : Object:=This._transporter.checkConnection()
				If (Bool($status.success))
					return "SMTP connection OK. Server: "+This._transporter.host+":"+String(This._transporter.port)
				Else
					return "SMTP connection failed: "+String($status.statusText)+" (status: "+String($status.status)+")"
				End if
			Catch
				return "Error checking SMTP connection: "+Last errors.last().message
			End try

		: ((This.provider="gmail") | (This.provider="outlook"))
			If (Length(This._netkitInitError)>0)
				return "NetKit "+This.provider+" configuration error: "+This._netkitInitError
			End if
			If (This._netkitService=Null)
				return "NetKit "+This.provider+" service is not configured."
			End if
			If ((This._netkitOAuth2Provider#Null) & (This._netkitOAuth2Provider.token#Null) & (Length(String(This._netkitOAuth2Provider.token.access_token))>0))
				return "NetKit "+This.provider+" is configured (OAuth token present)."
			End if
			return "NetKit "+This.provider+" is configured (token not acquired yet)."
	End case

	return "Error: Unsupported provider '"+This.provider+"'."

	// -----------------------------------------------------------------
	// MARK:- Internal helpers
	// -----------------------------------------------------------------

Function _initSMTP($transporterOrConfig : Object; $config : Object)

	If (OB Instance of($transporterOrConfig; 4D.SMTPTransporter))
		This._transporter:=$transporterOrConfig
		return
	End if

	var $serverConfig : Object:=($config.smtpServer#Null) ? $config.smtpServer : Null
	If (($serverConfig=Null) & ($transporterOrConfig#Null) & (Value type($transporterOrConfig)=Is object))
		$serverConfig:=$transporterOrConfig
	End if

	If (($serverConfig#Null) & (Value type($serverConfig)=Is object) & (Length(String($serverConfig.host))>0))
		This._transporter:=SMTP New transporter($serverConfig)
	End if

Function _initNetKit($config : Object)

	This._netkitInitError:=""

	// Accept pre-built OAuth2 provider object if supplied
	If ($config.oauth2Provider#Null)
		This._netkitOAuth2Provider:=$config.oauth2Provider
	End if

	If (This._netkitOAuth2Provider=Null)
		var $oauth2Params : Object:=($config.oauth2#Null) ? $config.oauth2 : Null
		If (($oauth2Params=Null) | (Value type($oauth2Params)#Is object))
			This._netkitInitError:="Missing oauth2 configuration object."
			return
		End if

		var $oauth2Class : Object:=This._resolveClass(["cs.NetKit.OAuth2Provider"; "cs.OAuth2Provider"])
		If ($oauth2Class=Null)
			This._netkitInitError:="OAuth2Provider class is unavailable (4D NetKit not loaded)."
			return
		End if

		Try
			This._netkitOAuth2Provider:=$oauth2Class.new($oauth2Params)
		Catch
			This._netkitInitError:="OAuth2 provider initialization failed: "+Last errors.last().message
			return
		End try
	End if

	var $providerOptions : Object:=($config.providerOptions#Null) ? OB Copy($config.providerOptions) : {}
	If (Length(String($providerOptions.mailType))=0)
		$providerOptions.mailType:=This.netkitMailType
	End if
	If (Length(This.netkitUserId)>0)
		$providerOptions.userId:=This.netkitUserId
	End if

	var $providerClass : Object:=Null
	If (This.provider="gmail")
		$providerClass:=This._resolveClass(["cs.NetKit.Google"; "cs.Google"])
	Else
		$providerClass:=This._resolveClass(["cs.NetKit.Office365"; "cs.Office365"])
	End if

	If ($providerClass=Null)
		This._netkitInitError:="Provider class is unavailable for '"+This.provider+"' (4D NetKit not loaded)."
		return
	End if

	Try
		This._netkitService:=$providerClass.new(This._netkitOAuth2Provider; $providerOptions)
	Catch
		This._netkitInitError:="Provider initialization failed: "+Last errors.last().message
	End try

Function _resolveClass($classCandidates : Collection) : Object

	var $candidate : Text
	For each ($candidate; $classCandidates)
		Try
			var $formula:=Formula from string($candidate)
			var $classObject : Variant:=$formula.call(Null)
			If ($classObject#Null)
				return $classObject
			End if
		Catch
			// try next candidate
		End try
	End for each
	return Null

Function _buildEmailObject($to : Text; $subject : Text; $body : Text; $htmlBody : Text; $cc : Text; $bcc : Text; $replyTo : Text) : Object

	var $email : Object:={}

	If (Length(This.fromAddress)>0)
		If (Length(This.fromName)>0)
			$email.from:=This.fromName+" <"+This.fromAddress+">"
		Else
			$email.from:=This.fromAddress
		End if
	End if

	$email.to:=$to
	$email.subject:=$subject
	$email.textBody:=$body

	If (Length($htmlBody)>0)
		$email.htmlBody:=$htmlBody
	End if
	If (Length($cc)>0)
		$email.cc:=$cc
	End if
	If (Length($bcc)>0)
		$email.bcc:=$bcc
	End if
	If (Length($replyTo)>0)
		$email.replyTo:=$replyTo
	End if

	return $email

Function _sendEmailWithProvider($email : Object; $to : Text; $cc : Text; $subject : Text) : Text

	Case of
		: (This.provider="smtp")
			return This._sendViaSMTP($email; $to; $cc; $subject)
		: ((This.provider="gmail") | (This.provider="outlook"))
			return This._sendViaNetKit($email; $to; $cc; $subject)
	End case

	return "Error: Unsupported provider '"+This.provider+"'."

Function _sendViaSMTP($email : Object; $to : Text; $cc : Text; $subject : Text) : Text

	If (This._transporter=Null)
		return "Error sending email: SMTP transporter is not configured."
	End if

	Try
		var $status : Object:=This._transporter.send($email)
		If (Bool($status.success))
			var $recipientList : Text:=$to
			If (Length($cc)>0)
				$recipientList:=$recipientList+", CC: "+$cc
			End if
			return "Email sent successfully to "+$recipientList+". Subject: \""+$subject+"\""
		Else
			return "Error sending email: "+This._statusMessage($status)
		End if
	Catch
		return "Error sending email: "+Last errors.last().message
	End try

Function _sendViaNetKit($email : Object; $to : Text; $cc : Text; $subject : Text) : Text

	If (Length(This._netkitInitError)>0)
		return "Error sending email via "+This.provider+": "+This._netkitInitError
	End if
	If ((This._netkitService=Null) | (This._netkitService.mail=Null))
		return "Error sending email via "+This.provider+": NetKit mail service is not configured."
	End if

	Try
		If (Length(This.netkitUserId)>0)
			This._netkitService.mail.userId:=This.netkitUserId
		End if

		var $status : Object:=This._netkitService.mail.send($email)
		If (Bool($status.success))
			var $recipientList : Text:=$to
			If (Length($cc)>0)
				$recipientList:=$recipientList+", CC: "+$cc
			End if
			return "Email sent successfully via "+This.provider+" to "+$recipientList+". Subject: \""+$subject+"\""
		Else
			return "Error sending email via "+This.provider+": "+This._statusMessage($status)
		End if
	Catch
		return "Error sending email via "+This.provider+": "+Last errors.last().message
	End try

Function _statusMessage($status : Object) : Text

	var $msg : Text:=String($status.statusText)
	If (Length($msg)=0)
		If (($status.errors#Null) & (Value type($status.errors)=Is collection) & ($status.errors.length>0))
			$msg:=String($status.errors[0].message)
		End if
	End if
	If (Length($msg)=0)
		$msg:=JSON Stringify($status; *)
	End if
	If ($status.status#Null)
		$msg:=$msg+" (status: "+String($status.status)+")"
	End if
	return $msg

Function _normalizeProvider($providerName : Text) : Text

	var $p : Text:=Lowercase(Trim($providerName))
	Case of
		: (($p="gmail") | ($p="google"))
			return "gmail"
		: (($p="outlook") | ($p="office365") | ($p="microsoft"))
			return "outlook"
		: ($p="smtp")
			return "smtp"
	End case
	return "smtp"

Function _parseAddresses($addresses : Text; $collection : Collection)

	var $cleaned : Text:=Replace string($addresses; ";"; ",")
	var $parts : Collection:=Split string($cleaned; ","; sk ignore empty strings+sk trim spaces)

	var $part : Text
	For each ($part; $parts)
		var $email : Text:=This._extractEmail($part)
		If (Length($email)>0)
			$collection.push($email)
		End if
	End for each

Function _extractEmail($input : Text) : Text

	var $text : Text:=Trim($input)
	If (Length($text)=0)
		return ""
	End if

	var $ltPos : Integer:=Position("<"; $text)
	var $gtPos : Integer:=Position(">"; $text)
	If (($ltPos>0) & ($gtPos>$ltPos))
		$text:=Substring($text; $ltPos+1; $gtPos-$ltPos-1)
	End if

	$text:=Trim($text)
	var $atPos : Integer:=Position("@"; $text)
	If ($atPos<=1)
		return ""
	End if

	var $domain : Text:=Substring($text; $atPos+1)
	If (Position("."; $domain)=0)
		return ""
	End if

	return Lowercase($text)

Function _getDomain($email : Text) : Text

	var $atPos : Integer:=Position("@"; $email)
	If ($atPos>0)
		return Lowercase(Substring($email; $atPos+1))
	End if
	return ""

Function _validateRecipientDomains($recipients : Collection) : Text

	If (This.allowedRecipientDomains.length=0)
		return ""
	End if

	var $email : Text
	For each ($email; $recipients)
		var $domain : Text:=This._getDomain($email)
		If (Length($domain)=0)
			return "Error: invalid email address '"+$email+"' (no domain)."
		End if
		If (Not(This._isDomainAllowed($domain)))
			return "Error: recipient domain '"+$domain+"' is not in the allowed list. Allowed domains: "+This.allowedRecipientDomains.join(", ")+"."
		End if
	End for each

	return ""

Function _isDomainAllowed($domain : Text) : Boolean

	var $allowed : Text
	For each ($allowed; This.allowedRecipientDomains)
		var $pattern : Text:=Lowercase($allowed)
		If ($pattern="*")
			return True
		End if

		If ($pattern[[1]]="*")
			var $suffix : Text:=Substring($pattern; 2)
			If ($domain=$suffix) | (("."+$domain)=$suffix) | (Position($suffix; $domain)=(Length($domain)-Length($suffix)+1))
				return True
			End if
		Else
			If ($domain=$pattern)
				return True
			End if
		End if
	End for each

	return False
