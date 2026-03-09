// AIToolApproval - Human-in-the-loop approval management tool
//
// Exposes approval queue and rule management to agents/users.
// Decision execution is always explicit through approval_decide.

property tools : Collection
property _engine : Object

Class constructor($config : Object)

	If ($config=Null)
		$config:={}
	End if

	If (($config.approvalEngine#Null) & (OB Instance of($config.approvalEngine; cs.ApprovalEngine)))
		This._engine:=$config.approvalEngine
	Else
		var $approvalConfig : Object:=($config.approvalConfig#Null) ? $config.approvalConfig : {}
		This._engine:=cs.ApprovalEngine.new($approvalConfig)
	End if

	This.tools:=[]

	This.tools.push({ \
		name: "approval_list_pending"; \
		description: "List all pending approval requests that require a human decision."; \
		parameters: {type: "object"; properties: {}; additionalProperties: False} \
	})

	This.tools.push({ \
		name: "approval_get_request"; \
		description: "Get details for a specific approval request by requestId."; \
		parameters: { \
			type: "object"; \
			properties: {requestId: {type: "string"; description: "Approval request id (apr_xxx)"}}; \
			required: ["requestId"]; \
			additionalProperties: False \
		} \
	})

	This.tools.push({ \
		name: "approval_decide"; \
		description: "Approve or reject a pending request. Optionally save a reusable allow/deny rule."; \
		parameters: { \
			type: "object"; \
			properties: { \
				requestId: {type: "string"; description: "Approval request id (apr_xxx)"}; \
				decision: {type: "string"; enum: ["allow"; "deny"]; description: "Decision for this request"}; \
				saveRule: {type: "boolean"; description: "Save decision as reusable rule"}; \
				ruleScope: {type: "string"; enum: ["session"; "user"; "project"]; description: "Scope for saved rule"}; \
				ttlSeconds: {type: "integer"; description: "Rule validity duration in seconds"}; \
				maxUses: {type: "integer"; description: "Maximum number of rule uses"}; \
				matcher: {type: "object"; description: "Structured matcher override for saved rule"}; \
				decisionReason: {type: "string"; description: "Optional reason for audit logs"}; \
				decidedBy: {type: "string"; description: "Actor id (e.g. user email/login)"} \
			}; \
			required: ["requestId"; "decision"]; \
			additionalProperties: False \
		} \
	})

	This.tools.push({ \
		name: "approval_list_rules"; \
		description: "List approval rules, optionally filtered by scope/tool/action."; \
		parameters: { \
			type: "object"; \
			properties: { \
				scope: {type: "string"; enum: ["session"; "user"; "project"]}; \
				tool: {type: "string"}; \
				action: {type: "string"} \
			}; \
			additionalProperties: False \
		} \
	})

	This.tools.push({ \
		name: "approval_delete_rule"; \
		description: "Disable a rule by rule id."; \
		parameters: { \
			type: "object"; \
			properties: {ruleId: {type: "string"; description: "Rule id (rul_xxx)"}}; \
			required: ["ruleId"]; \
			additionalProperties: False \
		} \
	})

Function approval_list_pending($params : Object) : Text

	var $pending : Collection:=This._engine.listPending()
	return JSON Stringify({success: True; pending: $pending}; *)

Function approval_get_request($params : Object) : Text

	var $id : Text:=String($params.requestId)
	If (Length($id)=0)
		return JSON Stringify({success: False; error: "requestId is required."})
	End if

	var $request : Object:=This._engine.getRequest($id)
	If ($request.error#Null)
		return JSON Stringify({success: False; error: String($request.error); requestId: $id})
	End if

	return JSON Stringify({success: True; request: $request}; *)

Function approval_decide($params : Object) : Text

	var $id : Text:=String($params.requestId)
	var $decision : Text:=Lowercase(String($params.decision))
	If ((Length($id)=0) | (($decision#"allow") & ($decision#"deny")))
		return JSON Stringify({success: False; error: "requestId and valid decision are required."})
	End if

	var $opts : Object:={}
	$opts.saveRule:=($params.saveRule#Null) ? Bool($params.saveRule) : False
	$opts.ruleScope:=($params.ruleScope#Null) ? String($params.ruleScope) : ""
	$opts.ttlSeconds:=($params.ttlSeconds#Null) ? Num($params.ttlSeconds) : 0
	$opts.maxUses:=($params.maxUses#Null) ? Num($params.maxUses) : 0
	$opts.matcher:=($params.matcher#Null) ? $params.matcher : Null
	$opts.decisionReason:=($params.decisionReason#Null) ? String($params.decisionReason) : ""
	$opts.decidedBy:=($params.decidedBy#Null) ? String($params.decidedBy) : "user"

	var $result : Object:=This._engine.decide($id; $decision; $opts)
	return JSON Stringify($result; *)

Function approval_list_rules($params : Object) : Text

	var $filter : Object:=($params#Null) ? $params : {}
	var $rules : Collection:=This._engine.listRules($filter)
	return JSON Stringify({success: True; rules: $rules}; *)

Function approval_delete_rule($params : Object) : Text

	var $id : Text:=String($params.ruleId)
	If (Length($id)=0)
		return JSON Stringify({success: False; error: "ruleId is required."})
	End if

	var $result : Object:=This._engine.deleteRule($id)
	return JSON Stringify($result; *)
