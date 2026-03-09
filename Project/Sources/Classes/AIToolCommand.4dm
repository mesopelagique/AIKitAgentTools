//%attributes = {"lang":"en","invisible":false,"shared":false}
// AIToolCommand — Execute shell commands via 4D.SystemWorker or PTY4D plugin
//
// ⚠️ HIGHEST RISK TOOL — arbitrary code execution
// Security: mandatory command whitelist, shell metacharacter blocking, timeout, output cap
//
// Backend selection:
// - executionBackend: "auto" (default), "pty", or "systemworker"
// - forceSystemWorker: True to bypass PTY even if plugin is present

property tools : Collection
property allowedCommands : Collection
property workingDirectory : Text
property timeout : Integer
property maxOutputSize : Integer
property blockMetacharacters : Boolean
property executionBackend : Text
property forceSystemWorker : Boolean
property ptyShell : Text
property ptyCols : Integer
property ptyRows : Integer
property ptyReadBufferSize : Integer
property ptyReadTimeoutMs : Integer
property ptyAvailable : Boolean
property ptyPluginName : Text
property _approvalEngine : Object

Class constructor($config : Object)

	If ($config=Null)
		$config:={}
	End if

	// --- Configuration ---
	// MANDATORY — no default "allow all"
	This.allowedCommands:=($config.allowedCommands#Null) ? $config.allowedCommands : []
	This.workingDirectory:=($config.workingDirectory#Null) ? String($config.workingDirectory) : ""
	This.timeout:=($config.timeout#Null) ? Num($config.timeout) : 30
	If (This.timeout<=0)
		This.timeout:=30
	End if
	This.maxOutputSize:=($config.maxOutputSize#Null) ? Num($config.maxOutputSize) : 50000
	If (This.maxOutputSize<=0)
		This.maxOutputSize:=50000
	End if
	This.blockMetacharacters:=($config.blockMetacharacters#Null) ? Bool($config.blockMetacharacters) : True

	This.executionBackend:=This._normalizeBackend(($config.executionBackend#Null) ? String($config.executionBackend) : "auto")
	This.forceSystemWorker:=($config.forceSystemWorker#Null) ? Bool($config.forceSystemWorker) : False

	This.ptyShell:=($config.ptyShell#Null) ? String($config.ptyShell) : "/bin/zsh"
	If (Length(This.ptyShell)=0)
		This.ptyShell:="/bin/zsh"
	End if
	This.ptyCols:=($config.ptyCols#Null) ? Num($config.ptyCols) : 120
	If (This.ptyCols<=0)
		This.ptyCols:=120
	End if
	This.ptyRows:=($config.ptyRows#Null) ? Num($config.ptyRows) : 30
	If (This.ptyRows<=0)
		This.ptyRows:=30
	End if
	This.ptyReadBufferSize:=($config.ptyReadBufferSize#Null) ? Num($config.ptyReadBufferSize) : 65536
	If (This.ptyReadBufferSize<=0)
		This.ptyReadBufferSize:=65536
	End if
	This.ptyReadTimeoutMs:=($config.ptyReadTimeoutMs#Null) ? Num($config.ptyReadTimeoutMs) : 200
	If (This.ptyReadTimeoutMs<=0)
		This.ptyReadTimeoutMs:=200
	End if

	var $pluginInfo : Object:=This._detectPTYPlugin()
	This.ptyAvailable:=Bool($pluginInfo.available)
	This.ptyPluginName:=String($pluginInfo.name)

	If (($config.approvalEngine#Null) & (OB Instance of($config.approvalEngine; cs.ApprovalEngine)))
		This._approvalEngine:=$config.approvalEngine
	Else
		var $approvalConfig : Object:=($config.approvalConfig#Null) ? $config.approvalConfig : {}
		This._approvalEngine:=cs.ApprovalEngine.new($approvalConfig)
	End if

	// --- Tool definitions ---
	This.tools:=[]
	This.tools.push({ \
		name: "run_command"; \
		description: "Execute a shell command and return its output. Backends: auto (default), pty, or systemworker. Only whitelisted commands are allowed."; \
		parameters: { \
			type: "object"; \
			properties: { \
				command: {type: "string"; description: "The command to execute (e.g. 'ls -la /tmp')"}; \
				backend: {type: "string"; enum: ["auto"; "pty"; "systemworker"]; description: "Optional per-call backend override"} \
			}; \
			required: ["command"]; \
			additionalProperties: False \
		} \
	})

Function run_command($params : Object) : Text

	var $command : Text:=Trim(String($params.command))

	If (Length($command)=0)
		return "Error: Command cannot be empty."
	End if

	// --- Validate whitelist ---
	If (This.allowedCommands.length=0)
		return "Error: No commands are whitelisted. Configure allowedCommands to enable command execution."
	End if

	// Extract the base command (first token)
	var $baseCommand : Text:=This._extractBaseCommand($command)

	If (Not(This._isCommandAllowed($baseCommand)))
		return "Error: Command '"+$baseCommand+"' is not in the allowed list. Allowed: "+This.allowedCommands.join(", ")
	End if

	// --- Block dangerous metacharacters ---
	var $hasMetacharacters : Boolean:=False
	If (This.blockMetacharacters)
		var $blocked : Text:=This._checkMetacharacters($command)
		If (Length($blocked)>0)
			$hasMetacharacters:=True
			return "Error: Command contains blocked shell metacharacter: '"+$blocked+"'. This is a security restriction."
		End if
	End if

	// --- Resolve execution backend ---
	var $requestedBackend : Text:=This._normalizeBackend(($params.backend#Null) ? String($params.backend) : This.executionBackend)
	var $backendInfo : Object:=This._resolveBackend($requestedBackend)
	var $activeBackend : Text:=String($backendInfo.backend)

	// --- Human approval gate ---
	var $approval : Object:=This._approvalEngine.evaluate({ \
		tool: "AIToolCommand"; \
		action: "run_command"; \
		summary: "Run command ("+$activeBackend+"): "+$command; \
		targetType: "command"; \
		targetValue: $command; \
		payload: { \
			command: $command; \
			baseCommand: $baseCommand; \
			workingDirectory: This.workingDirectory; \
			hasMetacharacters: $hasMetacharacters; \
			requestedBackend: $requestedBackend; \
			activeBackend: $activeBackend; \
			ptyAvailable: This.ptyAvailable \
		} \
	})
	If ($approval.status#"allowed")
		return JSON Stringify($approval; *)
	End if

	// --- Execute command ---
	var $result : Text:=""
	If ($activeBackend="pty")
		$result:=This._runWithPTY($command)
	Else
		$result:=This._runWithSystemWorker($command)
	End if

	If (Length(String($backendInfo.fallback))>0)
		$result:="[Backend fallback] "+String($backendInfo.fallback)+"\n"+$result
	End if

	return $result

Function _runWithSystemWorker($command : Text) : Text

	Try
		var $workerCommand : Text:=$command

		// Prefix with cd if workingDirectory is set
		If (Length(This.workingDirectory)>0)
			$workerCommand:="cd "+This._shellEscape(This.workingDirectory)+" && "+$command
		End if

		var $worker:=4D.SystemWorker.new($workerCommand)

		// Wait with timeout
		$worker.wait(This.timeout)

		var $stdout : Text:=""
		var $stderr : Text:=""

		If ($worker.responseError#Null)
			If (Value type($worker.responseError)=Is text)
				$stderr:=$worker.responseError
			Else
				If (Value type($worker.responseError)=Is BLOB)
					$stderr:=Convert to text($worker.responseError; "UTF-8")
				End if
			End if
		End if

		If ($worker.response#Null)
			If (Value type($worker.response)=Is text)
				$stdout:=$worker.response
			Else
				If (Value type($worker.response)=Is BLOB)
					$stdout:=Convert to text($worker.response; "UTF-8")
				End if
			End if
		End if

		var $output : Text:=""
		If (Length($stdout)>0)
			$output:=$stdout
		End if
		If (Length($stderr)>0)
			If (Length($output)>0)
				$output:=$output+"\n\n--- stderr ---\n"
			End if
			$output:=$output+$stderr
		End if
		If (Length($output)=0)
			$output:="Command completed with no output. Exit code: "+String($worker.exitCode)
		End if
		If ($worker.exitCode#0)
			$output:=$output+"\n\n[Exit code: "+String($worker.exitCode)+"]"
		End if

		return This._truncateOutput($output)

	Catch
		return "Error executing command: "+Last errors.last().message
	End try

Function _runWithPTY($command : Text) : Text

	var $cwd : Text:=This.workingDirectory
	If (Length($cwd)=0)
		$cwd:=Folder(fk database folder).path
	End if

	var $ptyId : Integer:=0
	var $output : Text:=""

	Try
		$ptyId:=This._ptyCreate(This.ptyShell; This.ptyCols; This.ptyRows; $cwd)
		If ($ptyId<=0)
			return This._runWithSystemWorker($command)
		End if

		// Drain prompt/banner first
		This._ptyDrain($ptyId; 100)

		var $marker : Text:="__AIKIT_PTY_DONE_"+String(Milliseconds)+"__"
		This._ptyWrite($ptyId; $command+Char(10))
		This._ptyWrite($ptyId; "echo "+$marker+":$?"+Char(10))

		var $deadline : Integer:=Milliseconds+(This.timeout*1000)
		var $rawOutput : Text:=""
		var $markerFound : Boolean:=False

		Repeat
			var $chunk : Text:=This._ptyRead($ptyId; This.ptyReadBufferSize; This.ptyReadTimeoutMs)
			If (Length($chunk)>0)
				$rawOutput:=$rawOutput+$chunk
				If (Position($marker; $rawOutput)>0)
					$markerFound:=True
				End if
			End if
		Until ($markerFound | (Milliseconds>=$deadline))

		var $parsed : Object:=This._parsePTYOutput($rawOutput; $marker)
		$output:=String($parsed.output)

		If (Length($output)=0)
			$output:="Command completed with no output."
		End if

		If (Not(Bool($parsed.markerFound)))
			$output:=$output+"\n\n[PTY timeout after "+String(This.timeout)+" seconds; partial output shown]"
		Else
			var $exitCode : Integer:=Num($parsed.exitCode)
			If ($exitCode#0)
				$output:=$output+"\n\n[Exit code: "+String($exitCode)+"]"
			End if
		End if

	Catch
		$output:="Error executing command via PTY: "+Last errors.last().message
	End try

	If ($ptyId>0)
		This._ptyClose($ptyId)
	End if

	return This._truncateOutput($output)

Function _truncateOutput($output : Text) : Text

	If (Length($output)>This.maxOutputSize)
		return Substring($output; 1; This.maxOutputSize)+"\n\n[Output truncated at "+String(This.maxOutputSize)+" characters]"
	End if
	return $output

Function _normalizeBackend($backend : Text) : Text

	var $value : Text:=Lowercase(Trim($backend))
	If (($value#"auto") & ($value#"pty") & ($value#"systemworker"))
		return "auto"
	End if
	return $value

Function _resolveBackend($requestedBackend : Text) : Object

	If (This.forceSystemWorker)
		return {backend: "systemworker"; fallback: "forceSystemWorker=True"}
	End if

	Case of
		: ($requestedBackend="systemworker")
			return {backend: "systemworker"; fallback: ""}
		: ($requestedBackend="pty")
			If (This.ptyAvailable)
				return {backend: "pty"; fallback: ""}
			End if
			return {backend: "systemworker"; fallback: "PTY plugin not available"}
	Else
		If (This.ptyAvailable)
			return {backend: "pty"; fallback: ""}
		End if
		return {backend: "systemworker"; fallback: ""}
	End case

Function _detectPTYPlugin() : Object

	ARRAY TEXT($pluginIndexes; 0x0)
	ARRAY TEXT($pluginNames; 0x0)
	var $i : Integer

	Try
		PLUGIN LIST($pluginIndexes; $pluginNames)
	Catch
		return {available: False; name: ""}
	End try

	For ($i; 1; Size of array($pluginNames))
		var $name : Text:=String($pluginNames{$i})
		If (Position("pty"; Lowercase($name))>0)
			return {available: True; name: $name}
		End if
	End for

	return {available: False; name: ""}

Function _ptyCreate($shell : Text; $cols : Integer; $rows : Integer; $cwd : Text) : Integer

	Try
		var $formula:=Formula from string("PTY Create")
		return Num($formula.call(This; $shell; $cols; $rows; $cwd))
	Catch
		return 0
	End try

Function _ptyWrite($ptyId : Integer; $text : Text) : Integer

	Try
		var $formula:=Formula from string("PTY Write")
		return Num($formula.call(This; $ptyId; $text))
	Catch
		return -1
	End try

Function _ptyRead($ptyId : Integer; $bufferSize : Integer; $timeoutMs : Integer) : Text

	Try
		var $formula:=Formula from string("PTY Read")
		var $raw : Variant:=$formula.call(This; $ptyId; $bufferSize; $timeoutMs)
		If (Value type($raw)=Is text)
			return $raw
		End if
		If (Value type($raw)=Is BLOB)
			return Convert to text($raw; "UTF-8")
		End if
	Catch
		// fallthrough
	End try

	return ""

Function _ptyClose($ptyId : Integer)

	Try
		var $formula:=Formula from string("PTY Close")
		$formula.call(This; $ptyId)
	Catch
		// ignore close errors
	End try

Function _ptyDrain($ptyId : Integer; $timeoutMs : Integer)

	var $chunk : Text
	Repeat
		$chunk:=This._ptyRead($ptyId; This.ptyReadBufferSize; $timeoutMs)
	Until (Length($chunk)=0)

Function _parsePTYOutput($rawOutput : Text; $marker : Text) : Object

	var $markerPos : Integer:=Position($marker; $rawOutput)
	If ($markerPos<=0)
		return {output: $rawOutput; exitCode: 0; markerFound: False}
	End if

	var $output : Text:=Substring($rawOutput; 1; $markerPos-1)
	var $cursor : Integer:=$markerPos+Length($marker)
	var $exitCode : Integer:=0

	If (Substring($rawOutput; $cursor; 1)=":")
		$cursor:=$cursor+1
		var $lineEnd : Integer:=Position(Char(10); $rawOutput; $cursor)
		If ($lineEnd=0)
			$lineEnd:=Length($rawOutput)+1
		End if
		var $exitText : Text:=Trim(Replace string(Substring($rawOutput; $cursor; $lineEnd-$cursor); Char(13); ""))
		If (Length($exitText)>0)
			$exitCode:=Num($exitText)
		End if
	End if

	return {output: $output; exitCode: $exitCode; markerFound: True}

Function _extractBaseCommand($command : Text) : Text

	// Get the first token (command name) from the full command string
	var $trimmed : Text:=Trim($command)
	var $pos : Integer:=Position(" "; $trimmed)
	If ($pos>0)
		return Substring($trimmed; 1; $pos-1)
	End if
	return $trimmed

Function _isCommandAllowed($baseCommand : Text) : Boolean

	var $cmd : Text
	For each ($cmd; This.allowedCommands)
		If (Lowercase($baseCommand)=Lowercase(String($cmd)))
			return True
		End if
	End for each
	return False

Function _checkMetacharacters($command : Text) : Text

	// Check for dangerous shell metacharacters that could enable injection
	var $dangerous : Collection:=["|"; ";"; "&&"; "||"; "`"; "$("; "#{"; ">>"; "<<"; ">"]
	var $token : Text
	For each ($token; $dangerous)
		If (Position($token; $command)>0)
			return $token
		End if
	End for each

	return ""

Function _shellEscape($text : Text) : Text

	// Escape a string for safe use in shell commands
	var $escaped : Text:=Replace string($text; "'"; "'\"'\"'"; *)
	return "'"+$escaped+"'"
