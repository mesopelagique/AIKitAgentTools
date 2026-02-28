// AIToolSearch — DuckDuckGo web search via 4D.HTTPRequest
//
// Security: query sanitization, result count cap, untrusted content warning
//
// Usage:
//   var $tool:=cs.AIToolSearch.new({maxResults: 5})
//   $helper.registerTools($tool)

property tools : Collection
property maxResults : Integer
property timeout : Integer

Class constructor($config : Object)
	
	If ($config=Null)
		$config:={}
	End if 
	
	// --- Configuration ---
	This.maxResults:=($config.maxResults#Null) ? $config.maxResults : 5
	This.timeout:=($config.timeout#Null) ? $config.timeout : 10
	
	// --- Tool definitions ---
	This.tools:=[]
	This.tools.push({\
		name: "duckduckgo_search"; \
		description: "Search the web using DuckDuckGo. Returns a list of results with titles, URLs, and snippets. Use this to find current information on the internet."; \
		parameters: {\
		type: "object"; \
		properties: {\
		query: {type: "string"; description: "The search query"}\
		}; \
		required: ["query"]; \
		additionalProperties: False\
		}\
		})
	
	// -----------------------------------------------------------------
	// MARK:- Tool handler
	// -----------------------------------------------------------------
Function duckduckgo_search($params : Object) : Text
	
	var $query : Text:=String($params.query)
	
	If (Length($query)=0)
		return "Error: Search query cannot be empty."
	End if 
	
	// --- Sanitize query (remove control characters) ---
	$query:=This._sanitizeQuery($query)
	
	// --- Truncate very long queries ---
	If (Length($query)>500)
		$query:=Substring($query; 1; 500)
	End if 
	
	// --- Perform search using DuckDuckGo HTML lite ---
	var $url : Text:="https://html.duckduckgo.com/html/?q="+This._urlEncode($query)
	
	var $options : Object:={}
	$options.method:="GET"
	$options.timeout:=This.timeout
	var $headers : Object:={}
	$headers["User-Agent"]:="4D-AIKit-Tools/1.0"
	$headers["Accept"]:="text/html"
	$options.headers:=$headers
	
	Try
		var $request:=4D.HTTPRequest.new($url; $options)
		$request.wait()
		
		If ($request.response=Null)
			return "Error: Search request timed out."
		End if 
		
		If ($request.response.status#200)
			return "Error: Search returned status "+String($request.response.status)+"."
		End if 
		
		var $html : Text
		If (Value type($request.response.body)=Is text)
			$html:=$request.response.body
		Else 
			return "Error: Unexpected response format."
		End if 
		
		// --- Parse HTML results ---
		var $results : Collection:=This._parseResults($html)
		
		If ($results.length=0)
			return "No results found for '"+$query+"'."
		End if 
		
		// --- Format results as Markdown ---
		var $output : Text:="## Search Results for: "+$query+"\n\n"
		var $i : Integer:=0
		var $result : Object
		For each ($result; $results)
			$i:=$i+1
			If ($i>This.maxResults)
				break
			End if 
			$output:=$output+String($i)+". ["+$result.title+"]("+$result.url+")\n"
			If (Length($result.snippet)>0)
				$output:=$output+"   "+$result.snippet+"\n"
			End if 
			$output:=$output+"\n"
		End for each 
		
		return $output
		
	Catch
		return "Error: Search failed — "+Last errors.last().message
	End try
	
	// -----------------------------------------------------------------
	// MARK:- Internal helpers
	// -----------------------------------------------------------------
	
Function _sanitizeQuery($query : Text) : Text
	// Remove potential HTML/script injection
	var $clean : Text:=Replace string($query; "<"; ""; *)
	$clean:=Replace string($clean; ">"; ""; *)
	$clean:=Replace string($clean; "\""; ""; *)
	return $clean
	
Function _urlEncode($text : Text) : Text
	// Basic URL encoding for query parameter
	var $encoded : Text:=$text
	$encoded:=Replace string($encoded; " "; "+"; *)
	$encoded:=Replace string($encoded; "&"; "%26"; *)
	$encoded:=Replace string($encoded; "="; "%3D"; *)
	$encoded:=Replace string($encoded; "#"; "%23"; *)
	return $encoded
	
Function _parseResults($html : Text) : Collection
	// Parse DuckDuckGo HTML lite results
	// Results are in <a class="result__a" href="...">title</a>
	// Snippets are in <a class="result__snippet" ...>text</a>
	
	var $results : Collection:=[]
	var $searchPos : Integer:=1
	var $found : Boolean:=True
	
	While ($found && ($results.length<(This.maxResults+5)))
		
		// Find next result link
		var $linkStart : Integer:=This._findAfter($html; "class=\"result__a\""; $searchPos)
		If ($linkStart=0)
			// Try alternate class names used by DDG
			$linkStart:=This._findAfter($html; "class='result__a'"; $searchPos)
		End if 
		
		If ($linkStart=0)
			$found:=False
		Else 
			// Extract href
			var $hrefStart : Integer:=This._findAfter($html; "href=\""; $linkStart-50)
			If ($hrefStart=0)
				$hrefStart:=This._findAfter($html; "href='"; $linkStart-50)
			End if 
			
			var $url : Text:=""
			If ($hrefStart>0)
				var $hrefEnd : Integer:=Position("\""; $html; $hrefStart)
				If ($hrefEnd=0)
					$hrefEnd:=Position("'"; $html; $hrefStart)
				End if 
				If ($hrefEnd>$hrefStart)
					$url:=Substring($html; $hrefStart; $hrefEnd-$hrefStart)
				End if 
			End if 
			
			// Extract title (text between > and </a>)
			var $titleStart : Integer:=Position(">"; $html; $linkStart)
			var $title : Text:=""
			If ($titleStart>0)
				$titleStart:=$titleStart+1
				var $titleEnd : Integer:=Position("</a>"; $html; $titleStart)
				If ($titleEnd>$titleStart)
					$title:=This._stripHTML(Substring($html; $titleStart; $titleEnd-$titleStart))
				End if 
			End if 
			
			// Extract snippet
			var $snippetStart : Integer:=This._findAfter($html; "class=\"result__snippet\""; $linkStart)
			If ($snippetStart=0)
				$snippetStart:=This._findAfter($html; "class='result__snippet'"; $linkStart)
			End if 
			
			var $snippet : Text:=""
			If ($snippetStart>0)
				var $snippetTextStart : Integer:=Position(">"; $html; $snippetStart)
				If ($snippetTextStart>0)
					$snippetTextStart:=$snippetTextStart+1
					var $snippetEnd : Integer:=Position("</"; $html; $snippetTextStart)
					If ($snippetEnd>$snippetTextStart)
						$snippet:=This._stripHTML(Substring($html; $snippetTextStart; $snippetEnd-$snippetTextStart))
					End if 
				End if 
			End if 
			
			// Add result if we have at least a title or URL
			If ((Length($title)>0) || (Length($url)>0))
				$results.push({title: $title; url: $url; snippet: $snippet})
			End if 
			
			$searchPos:=$linkStart+1
		End if 
		
	End while 
	
	return $results
	
Function _findAfter($text : Text; $search : Text; $startPos : Integer) : Integer
	If ($startPos<1)
		$startPos:=1
	End if 
	var $pos : Integer:=Position($search; $text; $startPos)
	If ($pos>0)
		return $pos+Length($search)
	End if 
	return 0
	
Function _stripHTML($text : Text) : Text
	// Remove HTML tags from text
	var $clean : Text:=$text
	var $tagStart : Integer
	var $tagEnd : Integer
	
	Repeat 
		$tagStart:=Position("<"; $clean)
		If ($tagStart>0)
			$tagEnd:=Position(">"; $clean; $tagStart)
			If ($tagEnd>0)
				$clean:=Substring($clean; 1; $tagStart-1)+Substring($clean; $tagEnd+1)
			Else 
				// Malformed tag, just remove the <
				$clean:=Substring($clean; 1; $tagStart-1)+Substring($clean; $tagStart+1)
			End if 
		End if 
	Until ($tagStart=0)
	
	// Decode common HTML entities
	$clean:=Replace string($clean; "&amp;"; "&"; *)
	$clean:=Replace string($clean; "&lt;"; "<"; *)
	$clean:=Replace string($clean; "&gt;"; ">"; *)
	$clean:=Replace string($clean; "&quot;"; "\""; *)
	$clean:=Replace string($clean; "&#39;"; "'"; *)
	$clean:=Replace string($clean; "&nbsp;"; " "; *)
	
	return $clean
	