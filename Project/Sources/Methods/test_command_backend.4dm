//%attributes = {}
// test_command_backend - deterministic backend tests for AIToolCommand

// -----------------------------------------------------------------
// 1) Force SystemWorker backend
// -----------------------------------------------------------------
var $sysTool:=cs.AIToolCommand.new({ \
	allowedCommands: ["echo"; "date"]; \
	forceSystemWorker: True; \
	approvalConfig: {requireApproval: False}; \
	timeout: 5 \
})

var $res : Text:=$sysTool.run_command({command: "echo systemworker-backend-ok"})
ASSERT(Position("systemworker-backend-ok"; $res)>0; "Forced SystemWorker backend must execute command.")

// -----------------------------------------------------------------
// 2) Auto backend (PTY if available, else SystemWorker)
// -----------------------------------------------------------------
var $autoTool:=cs.AIToolCommand.new({ \
	allowedCommands: ["echo"; "date"]; \
	executionBackend: "auto"; \
	approvalConfig: {requireApproval: False}; \
	timeout: 5 \
})

$res:=$autoTool.run_command({command: "echo auto-backend-ok"})
ASSERT(Position("auto-backend-ok"; $res)>0; "Auto backend must execute command.")

// -----------------------------------------------------------------
// 3) Requested PTY backend with safe fallback
// -----------------------------------------------------------------
var $ptyTool:=cs.AIToolCommand.new({ \
	allowedCommands: ["echo"; "date"]; \
	executionBackend: "pty"; \
	approvalConfig: {requireApproval: False}; \
	timeout: 5 \
})

$res:=$ptyTool.run_command({command: "echo pty-backend-ok"})
ASSERT(Position("pty-backend-ok"; $res)>0; "PTY backend (or fallback) must execute command.")

If ($ptyTool.ptyAvailable)
	ASSERT(Position("[Backend fallback]"; $res)=0; "No fallback note expected when PTY plugin is available.")
Else 
	ASSERT(Position("[Backend fallback] PTY plugin not available"; $res)>0; "Fallback note expected when PTY plugin is unavailable.")
End if 

// -----------------------------------------------------------------
// 4) Per-call backend override
// -----------------------------------------------------------------
$res:=$autoTool.run_command({command: "echo override-backend-ok"; backend: "systemworker"})
ASSERT(Position("override-backend-ok"; $res)>0; "Per-call backend override must work.")

// -----------------------------------------------------------------
// 5) Security regression checks
// -----------------------------------------------------------------
$res:=$autoTool.run_command({command: "rm -rf /tmp/forbidden"})
ASSERT(Position("not in the allowed list"; $res)>0; "Non-whitelisted command must be blocked.")

$res:=$autoTool.run_command({command: "echo hi; date"})
ASSERT(Position("blocked shell metacharacter"; $res)>0; "Metacharacter chaining must be blocked.")

ALERT("test_command_backend passed")
