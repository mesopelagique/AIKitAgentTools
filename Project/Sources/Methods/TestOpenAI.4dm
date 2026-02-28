//%attributes = {"invisible":true}
// Helper method to create an OpenAI client for tests
// Reads API key from ~/.openai file or uses environment
#DECLARE() : cs.AIKit.OpenAI
var $client:=cs.AIKit.OpenAI.new()

If ((Length($client.apiKey)=0) && (Folder(fk home folder).file(".openai").exists))
	$client.apiKey:=Folder(fk home folder).file(".openai").getText()
End if 

// Uncomment to use a different provider:
// $client.baseURL:="http://127.0.0.1:11434/v1"  // ollama

If (Length($client.apiKey)=0)
	ALERT("No API key found. Create a ~/.openai file with your OpenAI API key.")
	return Null
End if 

return $client
