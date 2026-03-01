//%attributes = {"lang":"en","invisible":false,"shared":false}
// AIToolCommand — Execute shell commands via 4D.SystemWorker
//
// ⚠️ HIGHEST RISK TOOL — arbitrary code execution
// Security: mandatory command whitelist, shell metacharacter blocking, timeout, output cap
//
// Usage:
//   var $tool:=cs.agtools.AITToolCommand.new({allowedCommands: ["ls"; "cat"; "grep"; "echo"; "date"]})
//   $helper.registerTools($tool)

property tools : Collection
property allowedCommands : Collection
property workingDirectory : Text
property timeout : Integer
property maxOutputSize : Integer
property blockMetacharacters : Boolean

Class constructor($config : Object)
	
	If ($config=Null:C1517)
		$config:={}
	End if 
	
	// --- Configuration ---
	// MANDATORY — no default "allow all"
	This:C1470.allowedCommands:=($config.allowedCommands#Null:C1517) ? $config.allowedCommands : New collection:C1472()
	This:C1470.workingDirectory:=($config.workingDirectory#Null:C1517) ? $config.workingDirectory : ""
	This:C1470.timeout:=($config.timeout#Null:C1517) ? $config.timeout : 30
	This:C1470.maxOutputSize:=($config.maxOutputSize#Null:C1517) ? $config.maxOutputSize : 50000  // 50KB default
	This:C1470.blockMetacharacters:=($config.blockMetacharacters#Null:C1517) ? $config.blockMetacharacters : True:C214  // Block by default
	
	// --- Tool definitions ---
	This:C1470.tools:=[]
	This:C1470.tools.push({\
		name: "run_command"; \
		description: "Execute a shell command and return its output. Only whitelisted commands are allowed."; \
		parameters: {\
		type: "object"; \
		properties: {\
		command: {type: "string"; description: "The command to execute (e.g. 'ls -la /tmp')"}\
		}; \
		required: ["command"]; \
		additionalProperties: False:C215\
		}\
		})
	
	// -----------------------------------------------------------------
	// MARK:- Tool handler
	// -----------------------------------------------------------------
Function run_command($params : Object) : Text
	
	var $command : Text:=String:C10($params.command)
	
	If (Length:C16($command)=0)
		return "Error: Command cannot be empty."
	End if 
	
	// --- Validate whitelist ---
	If (This:C1470.allowedCommands.length=0)
		return "Error: No commands are whitelisted. Configure allowedCommands to enable command execution."
	End if 
	
	// Extract the base command (first token)
	var $baseCommand : Text:=This:C1470._extractBaseCommand($command)
	
	If (Not:C34(This:C1470._isCommandAllowed($baseCommand)))
		return "Error: Command '"+$baseCommand+"' is not in the allowed list. Allowed: "+This:C1470.allowedCommands.join(", ")
	End if 
	
	// --- Block dangerous metacharacters ---
	If (This:C1470.blockMetacharacters)
		var $blocked : Text:=This:C1470._checkMetacharacters($command)
		If (Length:C16($blocked)>0)
			return "Error: Command contains blocked shell metacharacter: '"+$blocked+"'. This is a security restriction."
		End if 
	End if 
	
	// --- Execute command ---
	Try
		var $workerCommand : Text:=$command
		
		// Prefix with cd if workingDirectory is set
		If (Length:C16(This:C1470.workingDirectory)>0)
			$workerCommand:="cd "+This:C1470._shellEscape(This:C1470.workingDirectory)+" && "+$command
		End if 
		
		var $worker:=4D:C1709.SystemWorker.new($workerCommand)
		
		// Wait with timeout
		$worker.wait(This:C1470.timeout)
		
		var $stdout : Text:=""
		var $stderr : Text:=""
		
		If ($worker.responseError#Null:C1517)
			If (Value type:C1509($worker.responseError)=Is text:K8:3)
				$stderr:=$worker.responseError
			Else 
				If (Value type:C1509($worker.responseError)=Is BLOB:K8:12)
					$stderr:=Convert to text:C1012($worker.responseError; "UTF-8")
				End if 
			End if 
		End if 
		
		If ($worker.response#Null:C1517)
			If (Value type:C1509($worker.response)=Is text:K8:3)
				$stdout:=$worker.response
			Else 
				If (Value type:C1509($worker.response)=Is BLOB:K8:12)
					$stdout:=Convert to text:C1012($worker.response; "UTF-8")
				End if 
			End if 
		End if 
		
		// --- Build output ---
		var $output : Text:=""
		
		If (Length:C16($stdout)>0)
			$output:=$stdout
		End if 
		
		If (Length:C16($stderr)>0)
			If (Length:C16($output)>0)
				$output:=$output+"\n\n--- stderr ---\n"
			End if 
			$output:=$output+$stderr
		End if 
		
		If (Length:C16($output)=0)
			$output:="Command completed with no output. Exit code: "+String:C10($worker.exitCode)
		End if 
		
		// --- Truncate ---
		If (Length:C16($output)>This:C1470.maxOutputSize)
			$output:=Substring:C12($output; 1; This:C1470.maxOutputSize)+"\n\n[Output truncated at "+String:C10(This:C1470.maxOutputSize)+" characters]"
		End if 
		
		// Append exit code if non-zero
		If ($worker.exitCode#0)
			$output:=$output+"\n\n[Exit code: "+String:C10($worker.exitCode)+"]"
		End if 
		
		return $output
		
	Catch
		return "Error executing command: "+Last errors:C1799.last().message
	End try
	
	// -----------------------------------------------------------------
	// MARK:- Internal helpers
	// -----------------------------------------------------------------
	
Function _extractBaseCommand($command : Text) : Text
	// Get the first token (command name) from the full command string
	var $trimmed : Text:=$command
	// Remove leading spaces
	While (Substring:C12($trimmed; 1; 1)=" ")
		$trimmed:=Substring:C12($trimmed; 2)
	End while 
	
	// Find first space
	var $pos : Integer:=Position:C15(" "; $trimmed)
	If ($pos>0)
		return Substring:C12($trimmed; 1; $pos-1)
	End if 
	return $trimmed
	
Function _isCommandAllowed($baseCommand : Text) : Boolean
	var $cmd : Text
	For each ($cmd; This:C1470.allowedCommands)
		If (Lowercase:C14($baseCommand)=Lowercase:C14($cmd))
			return True:C214
		End if 
	End for each 
	return False:C215
	
Function _checkMetacharacters($command : Text) : Text
	// Check for dangerous shell metacharacters that could enable injection
	var $dangerous : Collection:=New collection:C1472("|"; ";"; "&&"; "||"; "`"; "$("; "#{"; ">>"; "<<"; ">")
	
	var $char : Text
	For each ($char; $dangerous)
		If (Position:C15($char; $command)>0)
			return $char
		End if 
	End for each 
	
	return ""  // no dangerous characters found
	
Function _shellEscape($text : Text) : Text
	// Escape a string for safe use in shell commands
	var $escaped : Text:=Replace string:C233($text; "'"; "'\"'\"'"; *)
	return "'"+$escaped+"'"
