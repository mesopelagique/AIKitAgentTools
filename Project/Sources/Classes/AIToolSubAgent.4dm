// AIToolSubAgent - Manage isolated sub-agent chat sessions
//
// Features:
// - Create isolated sub-agents with explicit allowed tools
// - Run tasks in one sub-agent or batch runs
// - In-memory registry for agents and runs
// - Safe defaults: no nested sub-agent creation, bounded limits

property tools : Collection
property _client : Object
property _toolRegistry : Object
property _agents : Collection
property _runs : Collection
property _allowNestedCreation : Boolean
property _defaultMaxParallel : Integer
property _defaultTimeoutSec : Integer
property _defaultMaxToolCalls : Integer
property _defaultMaxTokens : Integer

Class constructor($clientOrConfig : Object; $config : Object)

	// Flexible constructor:
	// - new(client; config)
	// - new(config) where config contains client
	If ($config=Null)
		If (($clientOrConfig#Null) & (Value type($clientOrConfig)=Is object))
			If ($clientOrConfig.chat=Null)
				$config:=$clientOrConfig
			Else 
				$config:={}
			End if
		Else 
			$config:={}
		End if
	End if

	This._client:=($config.client#Null) ? $config.client : Null
	If (($clientOrConfig#Null) & (Value type($clientOrConfig)=Is object))
		If ($clientOrConfig.chat#Null)
			This._client:=$clientOrConfig
		End if
	End if

	This._toolRegistry:=($config.toolRegistry#Null) ? $config.toolRegistry : {}
	This._allowNestedCreation:=($config.allowNestedCreation#Null) ? Bool($config.allowNestedCreation) : False
	This._defaultMaxParallel:=($config.defaultMaxParallel#Null) ? Num($config.defaultMaxParallel) : 2
	This._defaultTimeoutSec:=($config.defaultTimeoutSec#Null) ? Num($config.defaultTimeoutSec) : 60
	This._defaultMaxToolCalls:=($config.defaultMaxToolCalls#Null) ? Num($config.defaultMaxToolCalls) : 8
	This._defaultMaxTokens:=($config.defaultMaxTokens#Null) ? Num($config.defaultMaxTokens) : 12000

	If (This._defaultMaxParallel<=0)
		This._defaultMaxParallel:=2
	End if
	If (This._defaultTimeoutSec<=0)
		This._defaultTimeoutSec:=60
	End if
	If (This._defaultMaxToolCalls<=0)
		This._defaultMaxToolCalls:=8
	End if
	If (This._defaultMaxTokens<=0)
		This._defaultMaxTokens:=12000
	End if

	This._agents:=New collection()
	This._runs:=New collection()

	This.tools:=[]
	This.tools.push({ \
		name: "subagent_create"; \
		description: "Create a sub-agent session with explicit system prompt and allowed tool names."; \
		parameters: { \
			type: "object"; \
			properties: { \
				name: {type: "string"}; \
				systemPrompt: {type: "string"}; \
				allowedTools: {type: "array"; items: {type: "string"}}; \
				model: {type: "string"}; \
				limits: {type: "object"; description: "Optional limits: maxToolCalls, timeoutSec, maxTokens"} \
			}; \
			required: ["name"; "systemPrompt"]; \
			additionalProperties: False \
		} \
	})

	This.tools.push({ \
		name: "subagent_run"; \
		description: "Run a task in a sub-agent."; \
		parameters: { \
			type: "object"; \
			properties: { \
				agentId: {type: "string"}; \
				task: {type: "string"}; \
				input: {type: "object"}; \
				timeoutSec: {type: "integer"} \
			}; \
			required: ["agentId"; "task"]; \
			additionalProperties: False \
		} \
	})

	This.tools.push({ \
		name: "subagent_run_batch"; \
		description: "Run multiple sub-agent tasks. Parallel intent is accepted; current engine enforces bounded deterministic execution."; \
		parameters: { \
			type: "object"; \
			properties: { \
				runs: { \
					type: "array"; \
					items: { \
						type: "object"; \
						properties: { \
							agentId: {type: "string"}; \
							task: {type: "string"}; \
							input: {type: "object"}; \
							timeoutSec: {type: "integer"} \
						}; \
						required: ["agentId"; "task"]; \
						additionalProperties: False \
					} \
				}; \
				maxParallel: {type: "integer"}; \
				mergePolicy: {type: "string"; enum: ["concat"; "rank"; "vote"; "reducerPrompt"]}; \
				reducerPrompt: {type: "string"} \
			}; \
			required: ["runs"]; \
			additionalProperties: False \
		} \
	})

	This.tools.push({ \
		name: "subagent_get_result"; \
		description: "Get a stored run result by run id."; \
		parameters: { \
			type: "object"; \
			properties: {runId: {type: "string"}}; \
			required: ["runId"]; \
			additionalProperties: False \
		} \
	})

	This.tools.push({ \
		name: "subagent_list"; \
		description: "List active sub-agents."; \
		parameters: {type: "object"; properties: {}; additionalProperties: False} \
	})

	This.tools.push({ \
		name: "subagent_close"; \
		description: "Close a sub-agent by id."; \
		parameters: { \
			type: "object"; \
			properties: {agentId: {type: "string"}}; \
			required: ["agentId"]; \
			additionalProperties: False \
		} \
	})

Function subagent_create($params : Object) : Text

	var $name : Text:=Trim(String($params.name))
	var $systemPrompt : Text:=Trim(String($params.systemPrompt))
	var $allowedTools : Collection:=($params.allowedTools#Null) ? $params.allowedTools : New collection()
	var $model : Text:=($params.model#Null) ? String($params.model) : "gpt-4o-mini"
	var $limits : Object:=($params.limits#Null) ? $params.limits : {}

	If (Length($name)=0)
		return JSON Stringify({success: False; error: "name is required."})
	End if
	If (Length($systemPrompt)=0)
		return JSON Stringify({success: False; error: "systemPrompt is required."})
	End if

	var $agentId : Text:=This._newAgentId()
	var $agent : Object:={ \
		id: $agentId; \
		name: $name; \
		systemPrompt: $systemPrompt; \
		allowedTools: $allowedTools; \
		model: $model; \
		limits: { \
			maxToolCalls: ($limits.maxToolCalls#Null) ? Num($limits.maxToolCalls) : This._defaultMaxToolCalls; \
			timeoutSec: ($limits.timeoutSec#Null) ? Num($limits.timeoutSec) : This._defaultTimeoutSec; \
			maxTokens: ($limits.maxTokens#Null) ? Num($limits.maxTokens) : This._defaultMaxTokens \
		}; \
		createdAt: This._nowISO(); \
		closed: False \
	}

	This._agents.push($agent)
	return JSON Stringify({success: True; agentId: $agentId; agent: $agent}; *)

Function subagent_run($params : Object) : Text

	var $agentId : Text:=String($params.agentId)
	var $task : Text:=Trim(String($params.task))
	var $input : Object:=($params.input#Null) ? $params.input : {}
	var $timeoutSec : Integer:=($params.timeoutSec#Null) ? Num($params.timeoutSec) : 0

	If (Length($agentId)=0)
		return JSON Stringify({success: False; error: "agentId is required."})
	End if
	If (Length($task)=0)
		return JSON Stringify({success: False; error: "task is required."})
	End if

	var $agent : Object:=This._findAgent($agentId)
	If ($agent=Null)
		return JSON Stringify({success: False; error: "Agent not found."; agentId: $agentId})
	End if
	If (Bool($agent.closed))
		return JSON Stringify({success: False; error: "Agent is closed."; agentId: $agentId})
	End if

	var $runId : Text:=This._newRunId()
	var $run : Object:={ \
		id: $runId; \
		agentId: $agentId; \
		task: $task; \
		input: $input; \
		status: "running"; \
		startedAt: This._nowISO(); \
		completedAt: ""; \
		output: ""; \
		error: ""; \
		provenance: {model: $agent.model; allowedTools: $agent.allowedTools} \
	}
	This._runs.push($run)

	// Runtime guardrails and fallback behavior
	var $effectiveTimeout : Integer:=($timeoutSec>0) ? $timeoutSec : Num($agent.limits.timeoutSec)
	If ($effectiveTimeout<=0)
		$effectiveTimeout:=This._defaultTimeoutSec
	End if

	If ($agent.allowSubAgentCreation=True)
		If (Not(This._allowNestedCreation))
			$run.status:="failed"
			$run.error:="Nested sub-agent creation is disabled."
			$run.completedAt:=This._nowISO()
			return JSON Stringify({success: False; runId: $runId; error: $run.error}; *)
		End if
	End if

	If (This._client=Null)
		$run.status:="failed"
		$run.error:="No AI client configured for sub-agent execution."
		$run.completedAt:=This._nowISO()
		return JSON Stringify({success: False; runId: $runId; error: $run.error}; *)
	End if
	If (This._client.chat=Null)
		$run.status:="failed"
		$run.error:="No AI client configured for sub-agent execution."
		$run.completedAt:=This._nowISO()
		return JSON Stringify({success: False; runId: $runId; error: $run.error}; *)
	End if

	Try
		var $helper:=This._client.chat.create($agent.systemPrompt; {model: $agent.model})
		$helper.autoHandleToolCalls:=True

		// Register only explicitly allowed tools from registry
		var $toolName : Text
		For each ($toolName; $agent.allowedTools)
			If (This._toolRegistry#Null)
				If (This._toolRegistry[$toolName]#Null)
					$helper.registerTools(This._toolRegistry[$toolName])
				End if
			End if
		End for each

		var $prompt : Text:="Task:\n"+$task
		If (Value type($input)=Is object)
			$prompt:=$prompt+"\n\nInput:\n"+JSON Stringify($input; *)
		End if

		var $result : Object:=$helper.prompt($prompt)
		If (Bool($result.success))
			$run.status:="completed"
			$run.output:=String($result.choice.message.text)
			$run.error:=""
		Else
			$run.status:="failed"
			$run.output:=""
			$run.error:=JSON Stringify($result.errors; *)
		End if
		$run.completedAt:=This._nowISO()

		return JSON Stringify({ \
			success: Bool($result.success); \
			runId: $runId; \
			agentId: $agentId; \
			status: $run.status; \
			output: $run.output; \
			error: $run.error; \
			timeoutSec: $effectiveTimeout \
		}; *)
	Catch
		$run.status:="failed"
		$run.error:="Sub-agent execution error: "+Last errors.last().message
		$run.completedAt:=This._nowISO()
		return JSON Stringify({success: False; runId: $runId; error: $run.error}; *)
	End try

Function subagent_run_batch($params : Object) : Text

	var $runs : Collection:=($params.runs#Null) ? $params.runs : New collection()
	var $maxParallel : Integer:=($params.maxParallel#Null) ? Num($params.maxParallel) : This._defaultMaxParallel
	var $mergePolicy : Text:=($params.mergePolicy#Null) ? Lowercase(String($params.mergePolicy)) : "concat"
	var $reducerPrompt : Text:=($params.reducerPrompt#Null) ? String($params.reducerPrompt) : ""
	If ($maxParallel<=0)
		$maxParallel:=This._defaultMaxParallel
	End if
	If (($mergePolicy#"concat") & ($mergePolicy#"rank") & ($mergePolicy#"vote") & ($mergePolicy#"reducerprompt"))
		$mergePolicy:="concat"
	End if

	If ($runs.length=0)
		return JSON Stringify({success: False; error: "runs is required and cannot be empty."})
	End if

	// Deterministic bounded execution:
	// this implementation processes batch sequentially while preserving a parallel intent signal.
	var $results : Collection:=New collection()
	var $item : Object
	For each ($item; $runs)
		var $resText : Text:=This.subagent_run($item)
		$results.push(JSON Parse($resText))
	End for each
	var $merged : Object:=This._mergeBatchResults($results; $mergePolicy; $reducerPrompt)

	return JSON Stringify({ \
		success: True; \
		requestedParallel: $maxParallel; \
		executedMode: "sequential_deterministic"; \
		results: $results; \
		merged: $merged \
	}; *)

Function subagent_get_result($params : Object) : Text

	var $runId : Text:=String($params.runId)
	If (Length($runId)=0)
		return JSON Stringify({success: False; error: "runId is required."})
	End if

	var $run : Object:=This._findRun($runId)
	If ($run=Null)
		return JSON Stringify({success: False; error: "Run not found."; runId: $runId})
	End if

	return JSON Stringify({success: True; run: $run}; *)

Function subagent_list($params : Object) : Text

	var $list : Collection:=New collection()
	var $agent : Object
	For each ($agent; This._agents)
		If (Not(Bool($agent.closed)))
			$list.push({id: $agent.id; name: $agent.name; model: $agent.model; createdAt: $agent.createdAt; allowedTools: $agent.allowedTools})
		End if
	End for each
	return JSON Stringify({success: True; agents: $list}; *)

Function subagent_close($params : Object) : Text

	var $agentId : Text:=String($params.agentId)
	If (Length($agentId)=0)
		return JSON Stringify({success: False; error: "agentId is required."})
	End if

	var $agent : Object:=This._findAgent($agentId)
	If ($agent=Null)
		return JSON Stringify({success: False; error: "Agent not found."; agentId: $agentId})
	End if

	$agent.closed:=True
	return JSON Stringify({success: True; agentId: $agentId; closed: True})

	// -----------------------------------------------------------------
	// MARK:- Internal helpers
	// -----------------------------------------------------------------

Function _findAgent($agentId : Text) : Object

	var $a : Object
	For each ($a; This._agents)
		If (String($a.id)=String($agentId))
			return $a
		End if
	End for each
	return Null

Function _findRun($runId : Text) : Object

	var $r : Object
	For each ($r; This._runs)
		If (String($r.id)=String($runId))
			return $r
		End if
	End for each
	return Null

Function _newAgentId() : Text
	return "sag_"+String(Milliseconds)+"_"+String(Random)

Function _newRunId() : Text
	return "run_"+String(Milliseconds)+"_"+String(Random)

Function _nowISO() : Text
	return String(Current date; ISO date)+"T"+String(Current time; ISO time)

Function _mergeBatchResults($results : Collection; $policy : Text; $reducerPrompt : Text) : Object

	var $p : Text:=Lowercase($policy)
	If (($p#"concat") & ($p#"rank") & ($p#"vote") & ($p#"reducerprompt"))
		$p:="concat"
	End if

	var $successful : Collection:=New collection()
	var $r : Object
	For each ($r; $results)
		If (String($r.status)="completed")
			$successful.push($r)
		End if
	End for each

	If ($successful.length=0)
		return {strategy: $p; output: ""; notes: "No successful outputs to merge."}
	End if

	Case of
		: ($p="rank")
			var $bestOutput : Text:=""
			var $bestScore : Integer:=-1
			For each ($r; $successful)
				var $candidate : Text:=String($r.output)
				var $score : Integer:=Length($candidate)
				If ($score>$bestScore)
					$bestScore:=$score
					$bestOutput:=$candidate
				End if
			End for each
			return {strategy: "rank"; output: $bestOutput; score: $bestScore}

		: ($p="vote")
			var $counts : Object:={}
			var $bestVoteOutput : Text:=""
			var $bestVoteCount : Integer:=0
			For each ($r; $successful)
				var $candidateVote : Text:=String($r.output)
				If (Length($candidateVote)=0)
					// skip empty output
				Else
					If ($counts[$candidateVote]=Null)
						$counts[$candidateVote]:=0
					End if
					$counts[$candidateVote]:=Num($counts[$candidateVote])+1
					If (Num($counts[$candidateVote])>$bestVoteCount)
						$bestVoteCount:=Num($counts[$candidateVote])
						$bestVoteOutput:=$candidateVote
					End if
				End if
			End for each
			If (Length($bestVoteOutput)=0)
				// fallback when outputs are all empty
				$bestVoteOutput:=String($successful[0].output)
				$bestVoteCount:=1
			End if
			return {strategy: "vote"; output: $bestVoteOutput; votes: $bestVoteCount}

		: ($p="reducerprompt")
			var $combined : Text:=This._concatOutputs($successful)
			If (This._client=Null)
				return {strategy: "reducerPrompt"; output: $combined; notes: "No AI client available, used concat fallback."}
			End if
			If (This._client.chat=Null)
				return {strategy: "reducerPrompt"; output: $combined; notes: "No AI client available, used concat fallback."}
			End if
			Try
				var $prompt : Text:=Length($reducerPrompt)>0 ? $reducerPrompt : "Merge the following run outputs into one concise result."
				var $helper:=This._client.chat.create("You merge sub-agent outputs deterministically."; {model: "gpt-4o-mini"})
				var $reduced : Object:=$helper.prompt($prompt+"\n\n"+$combined)
				If (Bool($reduced.success))
					return {strategy: "reducerPrompt"; output: String($reduced.choice.message.text)}
				End if
				return {strategy: "reducerPrompt"; output: $combined; notes: "Reducer call failed, used concat fallback."}
			Catch
				return {strategy: "reducerPrompt"; output: $combined; notes: "Reducer error, used concat fallback."}
			End try

	Else
		return {strategy: "concat"; output: This._concatOutputs($successful)}
	End case

Function _concatOutputs($results : Collection) : Text

	var $parts : Collection:=New collection()
	var $r : Object
	For each ($r; $results)
		$parts.push(String($r.output))
	End for each
	return $parts.join("\n\n---\n\n")
