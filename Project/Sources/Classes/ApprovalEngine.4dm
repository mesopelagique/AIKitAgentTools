// ApprovalEngine - Human-in-the-loop approval engine with hybrid persistence
//
// Behavior:
// - Per-call approval by default (requireApproval = True)
// - Reusable allow/deny rules with scope/ttl/maxUses
// - Deny rules evaluated before allow rules
// - ORDA persistence when dataclasses are available, memory fallback otherwise
//
// Dataclass fields expected (if persistence enabled):
// AgentApprovalRule:
//   id, scope, tool, action, targetType, targetPattern, argConstraints,
//   decision, ttlSeconds, maxUses, uses, createdBy, createdAt, createdMs,
//   expiresAt, enabled
// AgentApprovalRequest:
//   id, tool, action, summary, payload, fingerprint, status,
//   requestedAt, expiresAt, decidedAt, decidedBy, decisionReason

property requireApproval : Boolean
property shadowMode : Boolean
property requestTTLSeconds : Integer
property defaultRuleScope : Text
property rulesDataclass : Text
property requestsDataclass : Text
property _persistent : Boolean
property _store : Object

Class constructor($config : Object)

	If ($config=Null)
		$config:={}
	End if

	// --- Core behavior ---
	This.requireApproval:=($config.requireApproval#Null) ? Bool($config.requireApproval) : True
	This.shadowMode:=($config.shadowMode#Null) ? Bool($config.shadowMode) : False
	This.requestTTLSeconds:=($config.requestTTLSeconds#Null) ? Num($config.requestTTLSeconds) : 600
	If (This.requestTTLSeconds<=0)
		This.requestTTLSeconds:=600
	End if

	This.defaultRuleScope:=($config.defaultRuleScope#Null) ? Lowercase(String($config.defaultRuleScope)) : "project"
	If (Length(This.defaultRuleScope)=0)
		This.defaultRuleScope:="project"
	End if

	This.rulesDataclass:=($config.rulesDataclass#Null) ? String($config.rulesDataclass) : "AgentApprovalRule"
	This.requestsDataclass:=($config.requestsDataclass#Null) ? String($config.requestsDataclass) : "AgentApprovalRequest"

	// --- In-memory fallback store ---
	// Keep storage instance-local to avoid shared object write constraints.
	This._store:=New object
	This._store.rules:=New collection()
	This._store.requests:=New collection()

	// --- ORDA persistence availability ---
	This._persistent:=False
	Try
		If ((ds[This.rulesDataclass]#Null) & (ds[This.requestsDataclass]#Null))
			This._persistent:=True
		End if
	Catch
		This._persistent:=False
	End try

	// Load persisted rules/requests once if available
	If (This._persistent)
		This._loadPersistent()
	End if

Function evaluate($operation : Object) : Object

	If (Not(This.requireApproval))
		return {status: "allowed"; mode: "disabled"}
	End if

	This._cleanup()

	var $op : Object:=This._normalizeOperation($operation)

	// 1) Deny rules first
	var $denyRule : Object:=This._findMatchingRule($op; "deny")
	If ($denyRule#Null)
		This._consumeRule($denyRule)
		return { \
			status: "denied"; \
			ruleId: String($denyRule.id); \
			tool: $op.tool; \
			action: $op.action; \
			summary: $op.summary; \
			reason: "Denied by approval rule." \
		}
	End if

	// 2) Allow rules
	var $allowRule : Object:=This._findMatchingRule($op; "allow")
	If ($allowRule#Null)
		This._consumeRule($allowRule)
		return { \
			status: "allowed"; \
			ruleId: String($allowRule.id); \
			tool: $op.tool; \
			action: $op.action; \
			summary: $op.summary \
		}
	End if

	// 3) No rule -> pending (or shadow allow)
	var $request : Object:=This._createRequest($op)

	If (This.shadowMode)
		$request.status:="shadow"
		This._persistRequest($request)
		return { \
			status: "allowed"; \
			mode: "shadow"; \
			requestId: $request.id; \
			tool: $request.tool; \
			action: $request.action; \
			summary: $request.summary \
		}
	End if

	This._persistRequest($request)
	return { \
		status: "pending_approval"; \
		requestId: $request.id; \
		tool: $request.tool; \
		action: $request.action; \
		summary: $request.summary; \
		fingerprint: $request.fingerprint; \
		expiresAt: $request.expiresAt \
	}

Function listPending() : Collection

	This._cleanup()
	var $out : Collection:=New collection()
	var $r : Object
	For each ($r; This._store.requests)
		If ($r.status="pending")
			$out.push($r)
		End if
	End for each
	return $out

Function getRequest($requestId : Text) : Object

	var $r : Object:=This._findRequestById($requestId)
	If ($r#Null)
		return $r
	End if
	return {error: "Request not found."; requestId: $requestId}

Function decide($requestId : Text; $decision : Text; $options : Object) : Object

	If ($options=Null)
		$options:={}
	End if

	var $request : Object:=This._findRequestById($requestId)
	If ($request=Null)
		return {success: False; error: "Request not found."; requestId: $requestId}
	End if

	If ($request.status#"pending")
		return {success: False; error: "Request is not pending."; requestId: $requestId; status: $request.status}
	End if

	var $dec : Text:=Lowercase(String($decision))
	If (($dec#"allow") & ($dec#"deny"))
		return {success: False; error: "Decision must be 'allow' or 'deny'."}
	End if

	$request.status:=($dec="allow") ? "approved" : "rejected"
	$request.decidedAt:=This._nowISO()
	$request.decidedBy:=($options.decidedBy#Null) ? String($options.decidedBy) : "user"
	$request.decisionReason:=($options.decisionReason#Null) ? String($options.decisionReason) : ""
	This._persistRequest($request)

	// One-time decision always applies to exact fingerprint (prevent replay tampering)
	var $oneShotRule : Object:=This._buildRuleFromRequest($request; $dec; $options)
	$oneShotRule.id:=This._newRuleId()
	$oneShotRule.scope:="session"
	$oneShotRule.maxUses:=1
	$oneShotRule.uses:=0
	$oneShotRule.enabled:=True
	$oneShotRule.fingerprint:=$request.fingerprint
	$oneShotRule.targetPattern:=($oneShotRule.targetPattern#Null) ? String($oneShotRule.targetPattern) : "*"
	This._persistRule($oneShotRule)

	// Optional saved reusable rule
	If (Bool($options.saveRule))
		var $savedRule : Object:=This._buildRuleFromRequest($request; $dec; $options)
		$savedRule.id:=This._newRuleId()
		$savedRule.scope:=($options.ruleScope#Null) ? Lowercase(String($options.ruleScope)) : This.defaultRuleScope
		$savedRule.maxUses:=($options.maxUses#Null) ? Num($options.maxUses) : 50
		If ($savedRule.maxUses<=0)
			$savedRule.maxUses:=50
		End if
		$savedRule.uses:=0
		$savedRule.enabled:=True
		$savedRule.fingerprint:=""  // reusable rule, not bound to single fingerprint
		This._persistRule($savedRule)
	End if

	return { \
		success: True; \
		requestId: $requestId; \
		status: $request.status; \
		fingerprint: $request.fingerprint; \
		savedRule: Bool($options.saveRule) \
	}

Function listRules($filter : Object) : Collection

	If ($filter=Null)
		$filter:={}
	End if

	This._cleanup()
	var $out : Collection:=New collection()
	var $rule : Object

	For each ($rule; This._store.rules)
		If (Not(Bool($rule.enabled)))
			// skip disabled
		Else
			var $ok : Boolean:=True
			If (($filter.scope#Null) & (Length(String($filter.scope))>0))
				$ok:=($ok & (Lowercase(String($rule.scope))=Lowercase(String($filter.scope))))
			End if
			If (($filter.tool#Null) & (Length(String($filter.tool))>0))
				$ok:=($ok & (Lowercase(String($rule.tool))=Lowercase(String($filter.tool))))
			End if
			If (($filter.action#Null) & (Length(String($filter.action))>0))
				$ok:=($ok & (Lowercase(String($rule.action))=Lowercase(String($filter.action))))
			End if
			If ($ok)
				$out.push($rule)
			End if
		End if
	End for each

	return $out

Function deleteRule($ruleId : Text) : Object

	var $rule : Object:=This._findRuleById($ruleId)
	If ($rule=Null)
		return {success: False; error: "Rule not found."; ruleId: $ruleId}
	End if

	$rule.enabled:=False
	This._persistRule($rule)
	return {success: True; ruleId: $ruleId}

	// -----------------------------------------------------------------
	// MARK:- Internal
	// -----------------------------------------------------------------

Function _normalizeOperation($operation : Object) : Object

	var $op : Object:=($operation#Null) ? $operation : {}
	$op.tool:=($op.tool#Null) ? String($op.tool) : "UnknownTool"
	$op.action:=($op.action#Null) ? String($op.action) : "unknown_action"
	$op.summary:=($op.summary#Null) ? String($op.summary) : ($op.tool+"."+$op.action)
	$op.targetType:=($op.targetType#Null) ? Lowercase(String($op.targetType)) : ""
	$op.targetValue:=($op.targetValue#Null) ? String($op.targetValue) : ""
	$op.payload:=($op.payload#Null) ? $op.payload : {}
	$op.fingerprint:=This._buildFingerprint($op)
	return $op

Function _createRequest($op : Object) : Object

	var $nowMs : Integer:=Milliseconds
	var $expiresMs : Integer:=$nowMs+(This.requestTTLSeconds*1000)

	return { \
		id: This._newRequestId(); \
		tool: $op.tool; \
		action: $op.action; \
		summary: $op.summary; \
		payload: $op.payload; \
		targetType: $op.targetType; \
		targetValue: $op.targetValue; \
		fingerprint: $op.fingerprint; \
		status: "pending"; \
		requestedAt: This._nowISO(); \
		requestedMs: $nowMs; \
		expiresAt: This._msToLabel($expiresMs); \
		expiresMs: $expiresMs; \
		decidedAt: ""; \
		decidedBy: ""; \
		decisionReason: "" \
	}

Function _buildRuleFromRequest($request : Object; $decision : Text; $options : Object) : Object

	var $matcher : Object:=($options.matcher#Null) ? $options.matcher : {}
	var $ttl : Integer:=($options.ttlSeconds#Null) ? Num($options.ttlSeconds) : 86400
	If ($ttl<=0)
		$ttl:=86400
	End if

	return { \
		scope: ""; \
		tool: ($matcher.tool#Null) ? String($matcher.tool) : String($request.tool); \
		action: ($matcher.action#Null) ? String($matcher.action) : String($request.action); \
		targetType: ($matcher.targetType#Null) ? Lowercase(String($matcher.targetType)) : Lowercase(String($request.targetType)); \
		targetPattern: ($matcher.targetPattern#Null) ? String($matcher.targetPattern) : String($request.targetValue); \
		argConstraints: ($matcher.argConstraints#Null) ? $matcher.argConstraints : {}; \
		decision: Lowercase(String($decision)); \
		ttlSeconds: $ttl; \
		maxUses: 50; \
		uses: 0; \
		createdBy: ($options.decidedBy#Null) ? String($options.decidedBy) : "user"; \
		createdAt: This._nowISO(); \
		createdMs: Milliseconds; \
		expiresAt: ""; \
		enabled: True; \
		fingerprint: "" \
	}

Function _findMatchingRule($op : Object; $decision : Text) : Object

	var $rule : Object
	For each ($rule; This._store.rules)
		If (Bool($rule.enabled))
			If (Lowercase(String($rule.decision))=Lowercase($decision))
				If (This._ruleMatchesOperation($rule; $op))
					return $rule
				End if
			End if
		End if
	End for each
	return Null

Function _ruleMatchesOperation($rule : Object; $op : Object) : Boolean

	// Expired/disabled/uses exceeded are handled by cleanup, but check again for safety
	If (Not(Bool($rule.enabled)))
		return False
	End if
	If (This._isRuleExpired($rule))
		return False
	End if
	If (Num($rule.maxUses)>0)
		If (Num($rule.uses)>=Num($rule.maxUses))
			return False
		End if
	End if

	// Fingerprint-bound one-shot rule
	If (Length(String($rule.fingerprint))>0)
		return (String($rule.fingerprint)=String($op.fingerprint))
	End if

	// Structured matcher fields
	If ((Length(String($rule.tool))>0) & (Lowercase(String($rule.tool))#Lowercase(String($op.tool))))
		return False
	End if
	If ((Length(String($rule.action))>0) & (Lowercase(String($rule.action))#Lowercase(String($op.action))))
		return False
	End if
	If ((Length(String($rule.targetType))>0) & (Lowercase(String($rule.targetType))#Lowercase(String($op.targetType))))
		return False
	End if

	var $pattern : Text:=String($rule.targetPattern)
	If (Length($pattern)>0)
		If (Not(This._matchesPattern(String($op.targetValue); $pattern)))
			return False
		End if
	End if

	// argConstraints generic matching
	If (Value type($rule.argConstraints)=Is object)
		var $k : Text
		For each ($k; $rule.argConstraints)
			var $expected:=$rule.argConstraints[$k]
			Case of
				: ($k="cwdPrefix")
					If (Position(String($expected); String($op.payload.workingDirectory))#1)
						return False
					End if
				: ($k="denyMetacharacters")
					If (Bool($expected))
						If (Bool($op.payload.hasMetacharacters))
							return False
						End if
					End if
				Else
					If (String($op.payload[$k])#String($expected))
						return False
					End if
			End case
		End for each
	End if

	return True

Function _matchesPattern($value : Text; $pattern : Text) : Boolean

	If ($pattern="*")
		return True
	End if

	// exact match
	If ($value=$pattern)
		return True
	End if

	// contains wildcard variants
	var $startsWithWildcard : Boolean:=(Substring($pattern; 1; 1)="*")
	var $endsWithWildcard : Boolean:=(Substring($pattern; Length($pattern); 1)="*")

	If ($startsWithWildcard & $endsWithWildcard)
		var $mid : Text:=Substring($pattern; 2; Length($pattern)-2)
		return (Position($mid; $value)>0)
	End if

	If ($startsWithWildcard)
		var $suffix : Text:=Substring($pattern; 2)
		return (Position($suffix; $value)=(Length($value)-Length($suffix)+1))
	End if

	If ($endsWithWildcard)
		var $prefix : Text:=Substring($pattern; 1; Length($pattern)-1)
		return (Position($prefix; $value)=1)
	End if

	return False

Function _consumeRule($rule : Object)

	$rule.uses:=Num($rule.uses)+1
	If ((Num($rule.maxUses)>0) & (Num($rule.uses)>=Num($rule.maxUses)))
		$rule.enabled:=False
	End if
	This._persistRule($rule)

Function _cleanup()

	var $r : Object

	// Requests expiration
	For each ($r; This._store.requests)
		If (($r.status="pending") & (Num($r.expiresMs)>0))
			If (Milliseconds>Num($r.expiresMs))
				$r.status:="expired"
				$r.decidedAt:=This._nowISO()
				$r.decisionReason:="Request expired."
				This._persistRequest($r)
			End if
		End if
	End for each

	// Rule expiration
	var $rule : Object
	For each ($rule; This._store.rules)
		If (Bool($rule.enabled))
			If (This._isRuleExpired($rule))
				$rule.enabled:=False
				This._persistRule($rule)
			End if
		End if
	End for each

Function _isRuleExpired($rule : Object) : Boolean

	var $ttl : Integer:=Num($rule.ttlSeconds)
	If ($ttl<=0)
		return False
	End if

	var $createdMs : Integer:=Num($rule.createdMs)
	If ($createdMs<=0)
		return False
	End if

	return (Milliseconds>(($createdMs)+($ttl*1000)))

Function _persistRule($rule : Object)

	// Update/insert in memory
	var $existing : Object:=This._findRuleById(String($rule.id))
	If ($existing=Null)
		This._store.rules.push($rule)
	Else
		// object is by reference, no extra action required
	End if

	// Best-effort persistent mirror
	If (This._persistent)
		This._upsertDataclassRow(This.rulesDataclass; $rule)
	End if

Function _persistRequest($request : Object)

	// Update/insert in memory
	var $existing : Object:=This._findRequestById(String($request.id))
	If ($existing=Null)
		This._store.requests.push($request)
	Else
		// object is by reference, no extra action required
	End if

	// Best-effort persistent mirror
	If (This._persistent)
		This._upsertDataclassRow(This.requestsDataclass; $request)
	End if

Function _upsertDataclassRow($dcName : Text; $row : Object)

	Try
		var $dc : cs.DataClass:=ds[$dcName]
		If ($dc=Null)
			return
		End if

		var $sel : Object:=$dc.query("id = :1"; String($row.id))
		var $entity : Object
		If ($sel.length>0)
			$entity:=$sel.first()
		Else
			$entity:=$dc.new()
		End if

		var $k : Text
		For each ($k; $row)
			$entity[$k]:=$row[$k]
		End for each
		$entity.save()
	Catch
		// stay resilient: persistence must not break tool execution
	End try

Function _loadPersistent()

	Try
		var $rulesDC : cs.DataClass:=ds[This.rulesDataclass]
		var $reqDC : cs.DataClass:=ds[This.requestsDataclass]
		If (($rulesDC=Null) | ($reqDC=Null))
			return
		End if

		var $row : Object

		// Rules
		var $rules : Object:=$rulesDC.all()
		For each ($row; $rules)
			var $rule : Object:=This._entityToObject($row)
			If (Length(String($rule.id))>0)
				If (This._findRuleById(String($rule.id))=Null)
					This._store.rules.push($rule)
				End if
			End if
		End for each

		// Requests
		var $reqs : Object:=$reqDC.all()
		For each ($row; $reqs)
			var $req : Object:=This._entityToObject($row)
			If (Length(String($req.id))>0)
				If (This._findRequestById(String($req.id))=Null)
					This._store.requests.push($req)
				End if
			End if
		End for each
	Catch
		This._persistent:=False
	End try

Function _entityToObject($entity : Object) : Object

	// Keep explicit field mapping to avoid metadata noise
	var $obj : Object:={}
	var $k : Text
	var $keys : Collection:=New collection( \
		"id"; "scope"; "tool"; "action"; "targetType"; "targetPattern"; "argConstraints"; \
		"decision"; "ttlSeconds"; "maxUses"; "uses"; "createdBy"; "createdAt"; "createdMs"; \
		"expiresAt"; "expiresMs"; "enabled"; "fingerprint"; \
		"summary"; "payload"; "status"; "requestedAt"; "requestedMs"; "decidedAt"; "decidedBy"; "decisionReason"; "targetValue")

	For each ($k; $keys)
		$obj[$k]:=$entity[$k]
	End for each
	return $obj

Function _findRuleById($ruleId : Text) : Object

	var $rule : Object
	For each ($rule; This._store.rules)
		If (String($rule.id)=String($ruleId))
			return $rule
		End if
	End for each
	return Null

Function _findRequestById($requestId : Text) : Object

	var $request : Object
	For each ($request; This._store.requests)
		If (String($request.id)=String($requestId))
			return $request
		End if
	End for each
	return Null

Function _buildFingerprint($op : Object) : Text

	// Deterministic lightweight fingerprint (no crypto dependency)
	var $raw : Text:=String($op.tool)+"|"+String($op.action)+"|"+String($op.targetType)+"|"+String($op.targetValue)+"|"+JSON Stringify($op.payload; *)
	var $normalized : Text:=Lowercase($raw)
	var $len : Integer:=Length($normalized)
	var $head : Text:=Substring($normalized; 1; 24)
	var $tailStart : Integer:=1
	If ($len>24)
		$tailStart:=$len-23
	End if
	var $tail : Text:=Substring($normalized; $tailStart; 24)
	return "fp:"+String($len)+":"+Replace string($head+"|"+$tail; " "; "_"; *)

Function _newRuleId() : Text
	return "rul_"+String(Milliseconds)+"_"+String(Random)

Function _newRequestId() : Text
	return "apr_"+String(Milliseconds)+"_"+String(Random)

Function _nowISO() : Text
	return String(Current date; ISO date)+"T"+String(Current time; ISO time)

Function _msToLabel($ms : Integer) : Text
	// Human-readable fallback label for clients
	return "ms:"+String($ms)
