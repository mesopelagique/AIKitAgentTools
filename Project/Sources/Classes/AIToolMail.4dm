// AIToolMail — Send emails via a pre-configured SMTP transporter
//
// Security: recipient domain whitelist, max recipients, locked from address,
//           subject/body length caps, no attachments by default
//
// Usage (pass a transporter):
//   var $server:={host: "smtp.example.com"; port: 587; user: "bot@example.com"; password: "xxx"}
//   var $transporter:=SMTP New transporter($server)
//   var $mail:=cs.AIToolMail.new($transporter; { \
//     fromAddress: "bot@example.com"; \
//     allowedRecipientDomains: ["example.com"; "partner.org"] \
//   })
//   $helper.registerTools($mail)
//
// Usage (pass server config — transporter created internally):
//   var $mail:=cs.AIToolMail.new({host: "smtp.example.com"; user: "bot@example.com"; password: "xxx"}; { \
//     fromAddress: "bot@example.com"; \
//     allowedRecipientDomains: ["example.com"] \
//   })
//   $helper.registerTools($mail)
//
// Designed for future extension with 4D NetKit (Gmail / Outlook) providers.

property tools : Collection
property fromAddress : Text
property fromName : Text
property allowedRecipientDomains : Collection
property maxRecipients : Integer
property maxSubjectLength : Integer
property maxBodyLength : Integer
property _transporter : Object

Class constructor($transporterOrConfig : Object; $config : Object)
	
	If ($config=Null)
		$config:={}
	End if 
	
	// --- Determine if first arg is a transporter or a server config ---
	// If it has a .send() function, it's already a transporter; otherwise treat as server config
	If (OB Instance of($transporterOrConfig; 4D.SMTPTransporter))
		This._transporter:=$transporterOrConfig
	Else 
		// First arg is server config — create transporter from it
		This._transporter:=SMTP New transporter($transporterOrConfig)
	End if 
	
	// --- Security configuration ---
	This.fromAddress:=($config.fromAddress#Null) ? String($config.fromAddress) : ""
	This.fromName:=($config.fromName#Null) ? String($config.fromName) : ""
	This.allowedRecipientDomains:=($config.allowedRecipientDomains#Null) ? $config.allowedRecipientDomains : New collection()  // empty = all (⚠️ risky)
	This.maxRecipients:=($config.maxRecipients#Null) ? $config.maxRecipients : 5
	This.maxSubjectLength:=($config.maxSubjectLength#Null) ? $config.maxSubjectLength : 500
	This.maxBodyLength:=($config.maxBodyLength#Null) ? $config.maxBodyLength : 50000  // ~50KB
	
	// --- Tool definitions ---
	This.tools:=[]
	
	// 1. send_email
	This.tools.push({\
		name: "send_email"; \
		description: "Send an email via SMTP. Requires at least one recipient (to), a subject, and a body. The 'from' address is set by the server configuration and cannot be changed."; \
		parameters: {\
		type: "object"; \
		properties: {\
		to: {type: "string"; description: "Recipient email address(es), comma-separated for multiple. Example: 'alice@example.com' or 'alice@example.com,bob@example.com'"}; \
		subject: {type: "string"; description: "Email subject line"}; \
		body: {type: "string"; description: "Plain text email body"}; \
		htmlBody: {type: "string"; description: "Optional HTML email body. When provided, both plain text and HTML versions are sent (multipart/alternative)."}; \
		cc: {type: "string"; description: "Optional CC recipient(s), comma-separated"}; \
		bcc: {type: "string"; description: "Optional BCC recipient(s), comma-separated"}; \
		replyTo: {type: "string"; description: "Optional reply-to address"}\
		}; \
		required: ["to"; "subject"; "body"]; \
		additionalProperties: False\
		}\
		})
	
	// 2. check_connection
	This.tools.push({\
		name: "check_email_connection"; \
		description: "Check if the SMTP server connection is working. Returns connection status."; \
		parameters: {\
		type: "object"; \
		properties: {}; \
		additionalProperties: False\
		}\
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
	
	// --- Validate required fields ---
	If (Length($to)=0)
		return "Error: 'to' is required."
	End if 
	If (Length($subject)=0)
		return "Error: 'subject' is required."
	End if 
	If (Length($body)=0)
		return "Error: 'body' is required."
	End if 
	
	// --- Length checks ---
	If (Length($subject)>This.maxSubjectLength)
		return "Error: subject exceeds maximum length of "+String(This.maxSubjectLength)+" characters."
	End if 
	If (Length($body)>This.maxBodyLength)
		return "Error: body exceeds maximum length of "+String(This.maxBodyLength)+" characters."
	End if 
	If (Length($htmlBody)>This.maxBodyLength)
		return "Error: htmlBody exceeds maximum length of "+String(This.maxBodyLength)+" characters."
	End if 
	
	// --- Collect all recipients and validate ---
	var $allRecipients : Collection:=New collection()
	This._parseAddresses($to; $allRecipients)
	If (Length($cc)>0)
		This._parseAddresses($cc; $allRecipients)
	End if 
	If (Length($bcc)>0)
		This._parseAddresses($bcc; $allRecipients)
	End if 
	
	// --- Check recipient count ---
	If ($allRecipients.length=0)
		return "Error: no valid recipient addresses found."
	End if 
	If ($allRecipients.length>This.maxRecipients)
		return "Error: too many recipients ("+String($allRecipients.length)+"). Maximum allowed: "+String(This.maxRecipients)+"."
	End if 
	
	// --- Validate recipient domains ---
	var $domainError : Text:=This._validateRecipientDomains($allRecipients)
	If (Length($domainError)>0)
		return $domainError
	End if 
	
	// --- Build email object ---
	var $email : Object:=New object
	
	// From address — locked to configuration
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
	
	// --- Send ---
	Try
		var $status : Object:=This._transporter.send($email)
		
		If (Bool($status.success))
			var $recipientList : Text:=$to
			If (Length($cc)>0)
				$recipientList:=$recipientList+", CC: "+$cc
			End if 
			return "Email sent successfully to "+$recipientList+". Subject: \""+$subject+"\""
		Else 
			return "Error sending email: "+String($status.statusText)+" (status: "+String($status.status)+")"
		End if 
		
	Catch
		return "Error sending email: "+Last errors.last().message
	End try
	
Function check_email_connection($params : Object) : Text
	
	Try
		var $status : Object:=This._transporter.checkConnection()
		
		If (Bool($status.success))
			return "SMTP connection OK. Server: "+This._transporter.host+":"+String(This._transporter.port)
		Else 
			return "SMTP connection failed: "+String($status.statusText)+" (status: "+String($status.status)+")"
		End if 
		
	Catch
		return "Error checking connection: "+Last errors.last().message
	End try
	
	// -----------------------------------------------------------------
	// MARK:- Internal helpers
	// -----------------------------------------------------------------

Function _parseAddresses($addresses : Text; $collection : Collection)
	
	// Parse comma-separated or semicolon-separated email addresses
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
	
	// Extract email from formats like "Name <email@domain.com>" or "email@domain.com"
	var $text : Text:=Trim($input)
	
	If (Length($text)=0)
		return ""
	End if 
	
	// Check for angle bracket format: "Name <email>"
	var $ltPos : Integer:=Position("<"; $text)
	var $gtPos : Integer:=Position(">"; $text)
	
	If (($ltPos>0) & ($gtPos>$ltPos))
		$text:=Substring($text; $ltPos+1; $gtPos-$ltPos-1)
	End if 
	
	$text:=Trim($text)
	
	// Basic email validation: must contain @ and at least one dot after @
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
	
	// If no domain whitelist, allow all (⚠️ risky)
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
	
	return ""  // All valid
	
Function _isDomainAllowed($domain : Text) : Boolean
	
	var $allowed : Text
	For each ($allowed; This.allowedRecipientDomains)
		var $pattern : Text:=Lowercase($allowed)
		
		// Wildcard matching: "*.example.com" matches "sub.example.com"
		If ($pattern="*")
			return True
		End if 
		
		If ($pattern[[1]]="*")
			// *.domain.com — match domain or any subdomain
			var $suffix : Text:=Substring($pattern; 2)  // ".example.com"
			If ($domain=$suffix) | (("."+$domain)=$suffix) | (Position($suffix; $domain)=(Length($domain)-Length($suffix)+1))
				return True
			End if 
		Else 
			// Exact match
			If ($domain=$pattern)
				return True
			End if 
		End if 
	End for each 
	
	return False
