// AIToolWebFetch — Fetch web page content via 4D.HTTPRequest
// 
// Security: domain whitelist, response size cap, text-only content filtering
// 
// Usage:
//   var $tool:=cs.AIToolWebFetch.new({allowedDomains: ["*.example.com"; "api.github.com"]})
//   $helper.registerTools($tool)

property tools : Collection
property allowedDomains : Collection
property allowedMethods : Collection
property timeout : Integer
property userAgent : Text
property maxResponseSize : Integer
property allowedContentTypes : Collection

Class constructor($config : Object)
	
	If ($config=Null)
		$config:={}
	End if 
	
	// --- Configuration ---
	This.timeout:=($config.timeout#Null) ? $config.timeout : 10
	This.userAgent:=($config.userAgent#Null) ? $config.userAgent : "4D-AIKit-Tools/1.0"
	This.maxResponseSize:=($config.maxResponseSize#Null) ? $config.maxResponseSize : 100000  // 100KB default
	This.allowedDomains:=($config.allowedDomains#Null) ? $config.allowedDomains : New collection()  // empty = all allowed (⚠️ risky)
	This.allowedContentTypes:=($config.allowedContentTypes#Null) ? $config.allowedContentTypes : New collection("text/*"; "application/json"; "application/xml")
	This.allowedMethods:=($config.allowedMethods#Null) ? $config.allowedMethods : New collection("GET")  // only GET by default for safety
	
	// --- Tool definitions ---
	This.tools:=[]
	
	// Build method enum from allowedMethods
	var $methodEnum : Collection:=This.allowedMethods.map(Formula(Uppercase(String($1.value))))
	var $methodDesc : Text:="HTTP method. Allowed: "+$methodEnum.join(", ")+". Default: GET"
	
	var $toolDef : Object:={}
	$toolDef.name:="web_fetch"
	$toolDef.description:="Fetch content from a URL using HTTP. Supports GET, POST, PUT, PATCH, DELETE, HEAD for REST API interaction. Returns the response body as text."
	
	var $props : Object:={}
	$props.url:={type: "string"; description: "The full URL to fetch (must start with https://)"}
	$props.method:={type: "string"; description: $methodDesc; enum: $methodEnum}
	$props.body:={type: "string"; description: "Request body (for POST, PUT, PATCH). Send JSON as a string."}
	$props.headers:={type: "object"; description: "Additional HTTP headers as key-value pairs. Example: {\"Authorization\": \"Bearer token123\", \"Content-Type\": \"application/json\"}"}
	
	$toolDef.parameters:={}
	$toolDef.parameters.type:="object"
	$toolDef.parameters.properties:=$props
	$toolDef.parameters.required:=["url"]
	$toolDef.parameters.additionalProperties:=False
	
	This.tools.push($toolDef)
	
	// -----------------------------------------------------------------
	// MARK:- Tool handler
	// -----------------------------------------------------------------
Function web_fetch($params : Object) : Text
	
	var $url : Text:=String($params.url)
	var $method : Text:=($params.method#Null) ? Uppercase(String($params.method)) : "GET"
	
	// --- Validate HTTP method ---
	If (This.allowedMethods.length>0)
		var $upperAllowed : Collection:=This.allowedMethods.map(Formula(Uppercase(String($1.value))))
		If ($upperAllowed.indexOf($method)=-1)
			return "Error: HTTP method '"+$method+"' is not allowed. Allowed: "+$upperAllowed.join(", ")
		End if 
	End if 
	
	// --- Validate URL scheme ---
	If (Not($url="https://@") && Not($url="http://@"))
		return "Error: Invalid URL. Must start with https:// or http://"
	End if 
	
	// --- Domain whitelist ---
	If (This.allowedDomains.length>0)
		If (Not(This._isDomainAllowed($url)))
			return "Error: Domain not in the allowed list. Allowed: "+This.allowedDomains.join(", ")
		End if 
	End if 
	
	// --- Block private/internal IPs ---
	If (This._isInternalURL($url))
		return "Error: Access to internal/private network addresses is not allowed."
	End if 
	
	// --- Perform request ---
	var $options : Object:={}
	$options.method:=$method
	$options.timeout:=This.timeout
	var $headers : Object:={}
	$headers["User-Agent"]:=This.userAgent
	
	// Default Accept header based on method
	If (($method="GET") || ($method="HEAD"))
		$headers["Accept"]:="text/html, application/json, text/plain"
	Else 
		$headers["Accept"]:="application/json, text/plain"
	End if 
	
	// Merge custom headers from params
	If ($params.headers#Null)
		var $key : Text
		For each ($key; $params.headers)
			$headers[$key]:=String($params.headers[$key])
		End for each 
	End if 
	
	$options.headers:=$headers
	
	// Set body for methods that support it
	If (($method="POST") || ($method="PUT") || ($method="PATCH"))
		If ($params.body#Null)
			$options.body:=String($params.body)
			// Auto-set Content-Type if not provided
			If ($headers["Content-Type"]=Null)
				$headers["Content-Type"]:="application/json"
			End if 
		End if 
	End if 
	
	Try
		var $request:=4D.HTTPRequest.new($url; $options)
		$request.wait()
		
		If ($request.response=Null)
			return "Error: No response received (timeout or connection failure)."
		End if 
		
		var $status : Integer:=$request.response.status
		
		// --- For HEAD requests, return status and headers only ---
		If ($method="HEAD")
			var $headResult : Object:={status: $status}
			$headResult.headers:=$request.response.headers
			return JSON Stringify($headResult)
		End if 
		
		// --- For DELETE, 204 No Content is success ---
		If (($method="DELETE") && ($status=204))
			return JSON Stringify({status: 204; message: "Deleted successfully"})
		End if 
		
		// --- HTTP error handling ---
		Case of 
			: ($status=404)
				return "Error: Resource not found at "+$url+" (404)."
			: (($status=401) || ($status=403))
				return "Error: Not authorized to access "+$url+" ("+String($status)+")."
			: (($status>=400) && ($status<500))
				return "Error: Client error "+String($status)+" while requesting "+$url+"."
			: (($status>=500) && ($status<600))
				return "Error: Server error "+String($status)+" while requesting "+$url+"."
			: ($status<200) || ($status>=300)
				return "Error: Unexpected status "+String($status)+" while requesting "+$url+"."
		End case 
		
		// --- Content type check ---
		var $contentType : Text:=String($request.response.headers["Content-Type"])
		If (Not(This._isContentTypeAllowed($contentType)))
			return "Error: Response content type '"+$contentType+"' is not allowed. Only text-based content is accepted."
		End if 
		
		// --- Extract body ---
		var $body : Text
		If (Value type($request.response.body)=Is text)
			$body:=$request.response.body
		Else 
			If (Value type($request.response.body)=Is BLOB)
				$body:=BLOB to text($request.response.body; UTF8 text with length)
			Else 
				// fixme: could be object blob
				$body:=JSON Stringify($request.response.body)
			End if 
		End if 
		
		// --- Truncate if too large ---
		If (Length($body)>This.maxResponseSize)
			$body:=Substring($body; 1; This.maxResponseSize)+"\n\n[Content truncated at "+String(This.maxResponseSize)+" characters]"
		End if 
		
		return $body
		
	Catch
		return "Error: Request failed — "+Last errors.last().message
	End try
	
	// -----------------------------------------------------------------
	// MARK:- Internal helpers
	// -----------------------------------------------------------------
	
Function _isDomainAllowed($url : Text) : Boolean
	// Extract domain from URL
	var $domain : Text
	var $pos : Integer:=Position("://"; $url)
	If ($pos>0)
		$domain:=Substring($url; $pos+3)
		$pos:=Position("/"; $domain)
		If ($pos>0)
			$domain:=Substring($domain; 1; $pos-1)
		End if 
		// Remove port
		$pos:=Position(":"; $domain)
		If ($pos>0)
			$domain:=Substring($domain; 1; $pos-1)
		End if 
	Else 
		return False
	End if 
	
	var $pattern : Text
	For each ($pattern; This.allowedDomains)
		If ($pattern=("*.@"))  // wildcard prefix pattern like *.example.com
			var $suffix : Text:=Substring($pattern; 2)  // .example.com
			If (($domain=$suffix) || ($domain=("@"+$suffix)))
				return True
			End if 
		Else 
			If ($domain=$pattern)
				return True
			End if 
		End if 
	End for each 
	
	return False
	
Function _isInternalURL($url : Text) : Boolean
	// Block localhost, 127.x, 10.x, 192.168.x, 169.254.x, [::1], 0.0.0.0
	var $domain : Text
	var $pos : Integer:=Position("://"; $url)
	If ($pos>0)
		$domain:=Substring($url; $pos+3)
		$pos:=Position("/"; $domain)
		If ($pos>0)
			$domain:=Substring($domain; 1; $pos-1)
		End if 
		$pos:=Position(":"; $domain)
		If ($pos>0)
			$domain:=Substring($domain; 1; $pos-1)
		End if 
	Else 
		return True
	End if 
	
	$domain:=Lowercase($domain)
	
	If ($domain="localhost") || ($domain="[::1]") || ($domain="0.0.0.0")
		return True
	End if 
	
	// Check private IP ranges
	If ($domain="127.@") || ($domain="10.@") || ($domain="192.168.@") || ($domain="169.254.@") || ($domain="172.@")
		// For 172.x, check 172.16-31.x.x
		If ($domain="172.@")
			var $secondOctet : Text:=Substring($domain; 5)
			$pos:=Position("."; $secondOctet)
			If ($pos>0)
				$secondOctet:=Substring($secondOctet; 1; $pos-1)
				var $octet : Integer:=Num($secondOctet)
				If (($octet>=16) && ($octet<=31))
					return True
				End if 
			End if 
		Else 
			return True
		End if 
	End if 
	
	return False
	
Function _isContentTypeAllowed($contentType : Text) : Boolean
	If (Length($contentType)=0)
		return True  // no content-type header = allow
	End if 
	
	$contentType:=Lowercase($contentType)
	
	var $pattern : Text
	For each ($pattern; This.allowedContentTypes)
		$pattern:=Lowercase($pattern)
		If ($pattern=("@/*"))  // wildcard like text/*
			var $prefix : Text:=Substring($pattern; 1; Position("/"; $pattern)-1)
			If ($contentType=($prefix+"/@"))
				return True
			End if 
		Else 
			If ($contentType=($pattern+"@"))
				return True
			End if 
		End if 
	End for each 
	
	return False
	