// AIToolPlanning - Plan generation and execution with optional sub-agent orchestration
//
// Exposes:
// - generate_plan
// - validate_plan
// - run_plan
//
// Planning and execution are deterministic by default, with optional AI-assisted generation.

property tools : Collection
property _client : Object
property _subAgent : Object
property _plans : Collection
property _defaultMaxSteps : Integer
property _defaultAllowParallel : Boolean
property _defaultExecutionMode : Text
property _defaultFailureMode : Text

Class constructor($clientOrConfig : Object; $subAgentOrConfig : Object; $config : Object)

	If ($config=Null)
		If (($subAgentOrConfig=Null) & ($clientOrConfig#Null) & (Value type($clientOrConfig)=Is object))
			If ($clientOrConfig.chat=Null)
				$config:=$clientOrConfig
			Else 
				$config:={}
			End if
		Else 
			$config:={}
		End if
	End if

	// Flexible forms:
	// - new(client; subAgent; config)
	// - new(config)
	This._client:=($config.client#Null) ? $config.client : Null
	If (($clientOrConfig#Null) & (Value type($clientOrConfig)=Is object))
		If ($clientOrConfig.chat#Null)
			This._client:=$clientOrConfig
		End if
	End if

	If (($subAgentOrConfig#Null) & (OB Instance of($subAgentOrConfig; cs.AIToolSubAgent)))
		This._subAgent:=$subAgentOrConfig
	Else
		If (($subAgentOrConfig#Null) & (Value type($subAgentOrConfig)=Is object))
			$config:=$subAgentOrConfig
		End if
		This._subAgent:=($config.subAgentTool#Null) ? $config.subAgentTool : Null
	End if

	This._defaultMaxSteps:=($config.defaultMaxSteps#Null) ? Num($config.defaultMaxSteps) : 8
	If (This._defaultMaxSteps<=0)
		This._defaultMaxSteps:=8
	End if

	This._defaultAllowParallel:=($config.defaultAllowParallel#Null) ? Bool($config.defaultAllowParallel) : False
	This._defaultExecutionMode:=($config.defaultExecutionMode#Null) ? Lowercase(String($config.defaultExecutionMode)) : "sequential"
	If ((This._defaultExecutionMode#"sequential") & (This._defaultExecutionMode#"parallel"))
		This._defaultExecutionMode:="sequential"
	End if

	This._defaultFailureMode:=($config.defaultFailureMode#Null) ? Lowercase(String($config.defaultFailureMode)) : "fail_fast"
	If ((This._defaultFailureMode#"fail_fast") & (This._defaultFailureMode#"continue_with_warnings"))
		This._defaultFailureMode:="fail_fast"
	End if

	This._plans:=New collection()

	This.tools:=[]
	This.tools.push({ \
		name: "generate_plan"; \
		description: "Generate a structured execution plan from a goal."; \
		parameters: { \
			type: "object"; \
			properties: { \
				goal: {type: "string"}; \
				context: {type: "string"}; \
				maxSteps: {type: "integer"}; \
				allowParallel: {type: "boolean"} \
			}; \
			required: ["goal"]; \
			additionalProperties: False \
		} \
	})

	This.tools.push({ \
		name: "validate_plan"; \
		description: "Validate plan schema and dependency graph."; \
		parameters: { \
			type: "object"; \
			properties: { \
				plan: {type: "object"} \
			}; \
			required: ["plan"]; \
			additionalProperties: False \
		} \
	})

	This.tools.push({ \
		name: "run_plan"; \
		description: "Execute a plan sequentially or in parallel using sub-agents when available."; \
		parameters: { \
			type: "object"; \
			properties: { \
				planId: {type: "string"}; \
				plan: {type: "object"}; \
				executionMode: {type: "string"; enum: ["sequential"; "parallel"]}; \
				failureMode: {type: "string"; enum: ["fail_fast"; "continue_with_warnings"]}; \
				mergePolicy: {type: "string"; enum: ["concat"; "rank"; "vote"; "reducerPrompt"]}; \
				reducerPrompt: {type: "string"} \
			}; \
			additionalProperties: False \
		} \
	})

Function generate_plan($params : Object) : Text

	var $goal : Text:=Trim(String($params.goal))
	var $context : Text:=($params.context#Null) ? String($params.context) : ""
	var $maxSteps : Integer:=($params.maxSteps#Null) ? Num($params.maxSteps) : This._defaultMaxSteps
	var $allowParallel : Boolean:=($params.allowParallel#Null) ? Bool($params.allowParallel) : This._defaultAllowParallel

	If (Length($goal)=0)
		return JSON Stringify({success: False; error: "goal is required."})
	End if
	If ($maxSteps<=0)
		$maxSteps:=This._defaultMaxSteps
	End if

	var $plan : Object:=This._generateDeterministicPlan($goal; $context; $maxSteps; $allowParallel)
	This._plans.push($plan)

	return JSON Stringify({success: True; plan: $plan}; *)

Function validate_plan($params : Object) : Text

	var $plan : Object:=($params.plan#Null) ? $params.plan : Null
	If ($plan=Null)
		return JSON Stringify({success: False; errors: ["plan is required"]})
	End if

	var $errors : Collection:=This._validatePlanObject($plan)
	return JSON Stringify({success: ($errors.length=0); errors: $errors}; *)

Function run_plan($params : Object) : Text

	var $plan : Object:=Null
	var $planId : Text:=($params.planId#Null) ? String($params.planId) : ""

	If (Length($planId)>0)
		$plan:=This._findPlan($planId)
		If ($plan=Null)
			return JSON Stringify({success: False; error: "Plan not found."; planId: $planId})
		End if
	Else
		$plan:=($params.plan#Null) ? $params.plan : Null
	End if

	If ($plan=Null)
		return JSON Stringify({success: False; error: "Provide planId or plan."})
	End if

	var $validation : Collection:=This._validatePlanObject($plan)
	If ($validation.length>0)
		return JSON Stringify({success: False; error: "Invalid plan."; validationErrors: $validation}; *)
	End if

	var $executionMode : Text:=($params.executionMode#Null) ? Lowercase(String($params.executionMode)) : This._defaultExecutionMode
	If (($executionMode#"sequential") & ($executionMode#"parallel"))
		$executionMode:=This._defaultExecutionMode
	End if

	var $failureMode : Text:=($params.failureMode#Null) ? Lowercase(String($params.failureMode)) : This._defaultFailureMode
	If (($failureMode#"fail_fast") & ($failureMode#"continue_with_warnings"))
		$failureMode:=This._defaultFailureMode
	End if
	var $mergePolicy : Text:=($params.mergePolicy#Null) ? String($params.mergePolicy) : "concat"
	var $reducerPrompt : Text:=($params.reducerPrompt#Null) ? String($params.reducerPrompt) : ""

	var $steps : Collection:=$plan.steps
	var $completed : Collection:=New collection()
	var $artifacts : Object:={}
	var $remaining : Collection:=New collection()
	var $step : Object
	For each ($step; $steps)
		$remaining.push($step)
	End for each

	var $reportSteps : Collection:=New collection()
	var $success : Boolean:=True
	var $lastMerge : Object:=Null

	While ($remaining.length>0)
		var $ready : Collection:=This._getReadySteps($remaining; $completed)
		If ($ready.length=0)
			$success:=False
			$reportSteps.push({status: "failed"; stepId: ""; error: "Plan has unresolved dependencies or cycle."})
			Break
		End if

		// Parallel intent for currently ready nodes (deterministic bounded execution)
		If (($executionMode="parallel") & ($ready.length>1) & (This._subAgent#Null))
			var $batchRuns : Collection:=New collection()
			For each ($step; $ready)
				var $resolvedAgentId : Text:=This._resolveAgentForStep($step)
				$batchRuns.push({ \
					stepId: String($step.id); \
					agentId: $resolvedAgentId; \
					task: String($step.description); \
					input: {step: $step; artifacts: $artifacts} \
				})
			End for each

			var $batchResultText : Text:=This._runBatch($batchRuns; $mergePolicy; $reducerPrompt)
			var $batchResult : Object:=JSON Parse($batchResultText)
			If ($batchResult.merged#Null)
				$lastMerge:=$batchResult.merged
			End if
			var $i : Integer
			For ($i; 0; $ready.length-1)
				var $item : Object:={}
				If (($batchResult.results#Null) & ($batchResult.results.length>$i))
					$item:=$batchResult.results[$i]
				End if
				var $entry : Object:=This._mapRunResultToReport($item; String($ready[$i].id); "parallel_requested")
				$reportSteps.push($entry)
				If ($entry.status="completed")
					$completed.push($entry.stepId)
					$artifacts[$entry.stepId]:=$entry.output
				Else
					$success:=False
					If ($failureMode="fail_fast")
						$remaining:=New collection()
						Break
					End if
				End if
			End for
		Else
			// Sequential execution for this wave
			For each ($step; $ready)
				var $runResult : Object:=This._runSingleStep($step; $artifacts)
				$reportSteps.push($runResult)
				If ($runResult.status="completed")
					$completed.push($runResult.stepId)
					$artifacts[$runResult.stepId]:=$runResult.output
				Else
					$success:=False
					If ($failureMode="fail_fast")
						$remaining:=New collection()
						Break
					End if
				End if
			End for each
		End if

		// Remove processed ready steps from remaining
		$remaining:=This._removeProcessed($remaining; $ready)
	End while

	return JSON Stringify({ \
		success: $success; \
		planId: String($plan.planId); \
		executionMode: $executionMode; \
		failureMode: $failureMode; \
		mergePolicy: $mergePolicy; \
		steps: $reportSteps; \
		artifacts: $artifacts; \
		merged: $lastMerge; \
		provenance: {subAgentEnabled: (This._subAgent#Null)} \
	}; *)

	// -----------------------------------------------------------------
	// MARK:- Internal plan logic
	// -----------------------------------------------------------------

Function _generateDeterministicPlan($goal : Text; $context : Text; $maxSteps : Integer; $allowParallel : Boolean) : Object

	var $segments : Collection:=Split string($goal; " and "; sk ignore empty strings+sk trim spaces)
	If ($segments.length=0)
		$segments.push($goal)
	End if

	// Cap steps
	While ($segments.length>$maxSteps)
		$segments.remove($segments.length-1)
	End while

	var $steps : Collection:=New collection()
	var $i : Integer:=0
	var $segment : Text
	For each ($segment; $segments)
		$i:=$i+1
		var $id : Text:="s"+String($i)
		var $execution : Text:=(($allowParallel) & ($segments.length>1)) ? "parallel" : "sequential"
		var $profile : Text:=This._guessProfile($segment)
		var $dependsOn : Collection:=New collection()
		If (($execution="sequential") & ($i>1))
			$dependsOn.push("s"+String($i-1))
		End if
		$steps.push({ \
			id: $id; \
			title: This._toTitle($segment); \
			description: $segment; \
			dependsOn: $dependsOn; \
			execution: $execution; \
			subAgentProfile: $profile; \
			inputs: {context: $context}; \
			outputs: ["result_"+$id] \
		})
	End for each

	return { \
		planId: This._newPlanId(); \
		goal: $goal; \
		steps: $steps; \
		createdAt: This._nowISO() \
	}

Function _validatePlanObject($plan : Object) : Collection

	var $errors : Collection:=New collection()

	If (Length(String($plan.goal))=0)
		$errors.push("goal is required")
	End if
	If (Value type($plan.steps)#Is collection)
		$errors.push("steps must be a collection")
		return $errors
	End if
	If ($plan.steps.length=0)
		$errors.push("steps cannot be empty")
		return $errors
	End if

	var $ids : Collection:=New collection()
	var $step : Object
	For each ($step; $plan.steps)
		var $id : Text:=String($step.id)
		If (Length($id)=0)
			$errors.push("step id is required")
		Else
			If ($ids.indexOf($id)>=0)
				$errors.push("duplicate step id: "+$id)
			Else
				$ids.push($id)
			End if
		End if
		If (Length(String($step.title))=0)
			$errors.push("step "+$id+": title is required")
		End if
		If (Length(String($step.description))=0)
			$errors.push("step "+$id+": description is required")
		End if
		If (Value type($step.dependsOn)#Is collection)
			$errors.push("step "+$id+": dependsOn must be a collection")
		End if
		If ((String($step.execution)#"sequential") & (String($step.execution)#"parallel"))
			$errors.push("step "+$id+": execution must be sequential or parallel")
		End if
	End for each

	// Unknown dependencies
	For each ($step; $plan.steps)
		If (Value type($step.dependsOn)=Is collection)
			var $dep : Text
			For each ($dep; $step.dependsOn)
				If ($ids.indexOf(String($dep))<0)
					$errors.push("step "+String($step.id)+": unknown dependency "+String($dep))
				End if
			End for each
		End if
	End for each

	// Cycle detection via topological reduction
	If ($errors.length=0)
		var $tmpRemaining : Collection:=New collection()
		For each ($step; $plan.steps)
			$tmpRemaining.push($step)
		End for each
		var $tmpDone : Collection:=New collection()
		While ($tmpRemaining.length>0)
			var $ready : Collection:=This._getReadySteps($tmpRemaining; $tmpDone)
			If ($ready.length=0)
				$errors.push("dependency graph contains a cycle or unresolved dependency")
				Break
			End if
			For each ($step; $ready)
				$tmpDone.push(String($step.id))
			End for each
			$tmpRemaining:=This._removeProcessed($tmpRemaining; $ready)
		End while
	End if

	return $errors

Function _getReadySteps($remaining : Collection; $completedIds : Collection) : Collection

	var $ready : Collection:=New collection()
	var $step : Object
	For each ($step; $remaining)
		var $allDepsDone : Boolean:=True
		If (Value type($step.dependsOn)=Is collection)
			var $dep : Text
			For each ($dep; $step.dependsOn)
				If ($completedIds.indexOf(String($dep))<0)
					$allDepsDone:=False
					Break
				End if
			End for each
		End if
		If ($allDepsDone)
			$ready.push($step)
		End if
	End for each
	return $ready

Function _removeProcessed($remaining : Collection; $processed : Collection) : Collection

	var $out : Collection:=New collection()
	var $item : Object
	For each ($item; $remaining)
		var $keep : Boolean:=True
		var $p : Object
		For each ($p; $processed)
			If (String($p.id)=String($item.id))
				$keep:=False
				Break
			End if
		End for each
		If ($keep)
			$out.push($item)
		End if
	End for each
	return $out

Function _runSingleStep($step : Object; $artifacts : Object) : Object

	var $agentId : Text:=This._resolveAgentForStep($step)
	If (Length($agentId)=0)
		return {stepId: String($step.id); status: "failed"; output: ""; error: "No sub-agent available for step."; mode: "sequential"}
	End if

	var $runText : Text:=This._subAgent.subagent_run({ \
		agentId: $agentId; \
		task: String($step.description); \
		input: {step: $step; artifacts: $artifacts} \
	})
	var $runObj : Object:=JSON Parse($runText)

	return This._mapRunResultToReport($runObj; String($step.id); "sequential")

Function _runBatch($batchRuns : Collection; $mergePolicy : Text; $reducerPrompt : Text) : Text

	If (This._subAgent=Null)
		return JSON Stringify({success: False; executedMode: "none"; results: New collection()})
	End if
	return This._subAgent.subagent_run_batch({runs: $batchRuns; maxParallel: 2; mergePolicy: $mergePolicy; reducerPrompt: $reducerPrompt})

Function _mapRunResultToReport($runResult : Object; $defaultStepId : Text; $mode : Text) : Object

	var $stepId : Text:=$defaultStepId
	If (Length($stepId)=0)
		$stepId:=($runResult.stepId#Null) ? String($runResult.stepId) : ""
	End if

	var $status : Text:=""
	If ($runResult.status#Null)
		$status:=String($runResult.status)
	Else
		If (Bool($runResult.success))
			$status:="completed"
		Else
			$status:="failed"
		End if
	End if

	return { \
		stepId: $stepId; \
		status: $status; \
		output: ($runResult.output#Null) ? String($runResult.output) : ""; \
		error: ($runResult.error#Null) ? String($runResult.error) : ""; \
		runId: ($runResult.runId#Null) ? String($runResult.runId) : ""; \
		mode: (Length($mode)>0) ? $mode : "parallel_requested" \
	}

Function _resolveAgentForStep($step : Object) : Text

	If (This._subAgent=Null)
		return ""
	End if

	var $profile : Text:=String($step.subAgentProfile)
	If (Length($profile)=0)
		$profile:="generalist"
	End if

	// Reuse if an agent with this profile exists
	var $listObj : Object:=JSON Parse(This._subAgent.subagent_list({}))
	If ($listObj.success=True)
		var $a : Object
		For each ($a; $listObj.agents)
			If (String($a.name)=("profile:"+$profile))
				return String($a.id)
			End if
		End for each
	End if

	// Create a dedicated profile agent
	var $createText : Text:=This._subAgent.subagent_create({ \
		name: "profile:"+$profile; \
		systemPrompt: This._profilePrompt($profile); \
		allowedTools: ($step.inputs.allowedTools#Null) ? $step.inputs.allowedTools : New collection(); \
		model: "gpt-4o-mini"; \
		limits: {maxToolCalls: 8; timeoutSec: 60; maxTokens: 12000} \
	})
	var $create : Object:=JSON Parse($createText)
	If (Bool($create.success))
		return String($create.agentId)
	End if

	return ""

Function _profilePrompt($profile : Text) : Text
	Case of
		: (Lowercase($profile)="researcher")
			return "You are a focused research sub-agent. Produce concise factual outputs with sources when available."
		: (Lowercase($profile)="coder")
			return "You are a coding sub-agent. Return implementation-oriented outputs with clear assumptions."
	Else
		return "You are a general-purpose sub-agent. Complete the assigned task with concise structured output."
	End case

Function _guessProfile($text : Text) : Text
	var $t : Text:=Lowercase($text)
	If ((Position("search"; $t)>0) | (Position("research"; $t)>0) | (Position("analyze"; $t)>0))
		return "researcher"
	End if
	If ((Position("code"; $t)>0) | (Position("implement"; $t)>0) | (Position("refactor"; $t)>0))
		return "coder"
	End if
	return "generalist"

Function _toTitle($text : Text) : Text
	var $title : Text:=Trim($text)
	If (Length($title)>60)
		$title:=Substring($title; 1; 60)+"..."
	End if
	return Uppercase(Substring($title; 1; 1))+Substring($title; 2)

Function _findPlan($planId : Text) : Object
	var $plan : Object
	For each ($plan; This._plans)
		If (String($plan.planId)=String($planId))
			return $plan
		End if
	End for each
	return Null

Function _newPlanId() : Text
	return "pln_"+String(Milliseconds)+"_"+String(Random)

Function _nowISO() : Text
	return String(Current date; ISO date)+"T"+String(Current time; ISO time)
