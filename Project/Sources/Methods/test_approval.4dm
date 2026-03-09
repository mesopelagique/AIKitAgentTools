//%attributes = {}
// test_approval - Test ApprovalEngine and AIToolApproval behaviors

var $engine:=cs.ApprovalEngine.new({requireApproval: True; shadowMode: False; requestTTLSeconds: 300})

// -----------------------------------------------------------------
// 1) Pending approval required by default
// -----------------------------------------------------------------
var $op : Object:={ \
	tool: "AIToolCommand"; \
	action: "run_command"; \
	summary: "Run command: date"; \
	targetType: "command"; \
	targetValue: "date"; \
	payload: {command: "date"; baseCommand: "date"} \
}

var $res : Object:=$engine.evaluate($op)
ASSERT($res.status="pending_approval"; "Expected pending approval on first run.")
ASSERT(Length(String($res.requestId))>0; "Pending request must include requestId.")

// -----------------------------------------------------------------
// 2) Allow once -> next identical call allowed once, then pending again
// -----------------------------------------------------------------
var $decision : Object:=$engine.decide($res.requestId; "allow"; {saveRule: False; decidedBy: "tester"})
ASSERT(Bool($decision.success); "Allow-once decision must succeed.")

var $allowed : Object:=$engine.evaluate($op)
ASSERT($allowed.status="allowed"; "Allow-once must allow immediate replay.")

var $pendingAgain : Object:=$engine.evaluate($op)
ASSERT($pendingAgain.status="pending_approval"; "One-shot approval must not persist beyond one use.")

// -----------------------------------------------------------------
// 3) Save deny rule precedence
// -----------------------------------------------------------------
var $denyDecide : Object:=$engine.decide($pendingAgain.requestId; "deny"; { \
	saveRule: True; \
	ruleScope: "project"; \
	maxUses: 5; \
	ttlSeconds: 3600; \
	decidedBy: "tester"; \
	matcher: {tool: "AIToolCommand"; action: "run_command"; targetType: "command"; targetPattern: "date"} \
})
ASSERT(Bool($denyDecide.success); "Deny + saveRule must succeed.")

var $denyResult : Object:=$engine.evaluate($op)
ASSERT($denyResult.status="denied"; "Deny rule must block matching action.")

// -----------------------------------------------------------------
// 4) Fingerprint mismatch protection
// -----------------------------------------------------------------
var $otherOp : Object:={ \
	tool: "AIToolCommand"; \
	action: "run_command"; \
	summary: "Run command: ls"; \
	targetType: "command"; \
	targetValue: "ls"; \
	payload: {command: "ls"; baseCommand: "ls"} \
}
var $otherResult : Object:=$engine.evaluate($otherOp)
ASSERT(($otherResult.status="pending_approval") | ($otherResult.status="denied"); "Different payload must not auto-match one-shot approval.")

// -----------------------------------------------------------------
// 5) Rule listing and deletion
// -----------------------------------------------------------------
var $rules : Collection:=$engine.listRules({tool: "AIToolCommand"; action: "run_command"})
ASSERT($rules.length>0; "Expected at least one rule.")

var $ruleId : Text:=String($rules[0].id)
var $del : Object:=$engine.deleteRule($ruleId)
ASSERT(Bool($del.success); "Rule deletion must succeed.")

// -----------------------------------------------------------------
// 6) TTL expiry simulation
// -----------------------------------------------------------------
var $ttlOp : Object:={ \
	tool: "AIToolFileSystem"; \
	action: "delete_file"; \
	summary: "Delete file /tmp/x.txt"; \
	targetType: "path"; \
	targetValue: "/tmp/x.txt"; \
	payload: {file_path: "/tmp/x.txt"} \
}
var $ttlPending : Object:=$engine.evaluate($ttlOp)
ASSERT($ttlPending.status="pending_approval"; "TTL setup request must be pending.")

var $ttlSave : Object:=$engine.decide($ttlPending.requestId; "allow"; { \
	saveRule: True; \
	ruleScope: "project"; \
	ttlSeconds: 1; \
	maxUses: 10; \
	decidedBy: "tester"; \
	matcher: {tool: "AIToolFileSystem"; action: "delete_file"; targetType: "path"; targetPattern: "/tmp/*"} \
})
ASSERT(Bool($ttlSave.success); "TTL rule creation must succeed.")

// Force-expire latest created rule in memory store for deterministic test
var $rule : Object
For each ($rule; $engine._store.rules)
	If ((String($rule.tool)="AIToolFileSystem") & (String($rule.action)="delete_file"))
		$rule.createdMs:=Milliseconds-(Num($rule.ttlSeconds)*1000)-1
	End if
End for each

var $ttlAfter : Object:=$engine.evaluate($ttlOp)
ASSERT($ttlAfter.status="pending_approval"; "Expired rule must not allow action.")

ALERT("test_approval passed")
