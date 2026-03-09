//%attributes = {}
// test_planning - Test AIToolPlanning schema validation and deterministic execution

var $subAgent:=cs.AIToolSubAgent.new({defaultMaxParallel: 2})
var $planner:=cs.AIToolPlanning.new({subAgentTool: $subAgent; defaultMaxSteps: 6; defaultAllowParallel: True})

// -----------------------------------------------------------------
// 1) Generate plan
// -----------------------------------------------------------------
var $generatedText : Text:=$planner.generate_plan({ \
	goal: "Collect requirements and design API and write test strategy"; \
	context: "Project is AI tools"; \
	allowParallel: True; \
	maxSteps: 6 \
})
var $generated : Object:=JSON Parse($generatedText)
ASSERT(Bool($generated.success); "generate_plan must succeed.")
ASSERT(Length(String($generated.plan.planId))>0; "Generated plan must have planId.")
ASSERT($generated.plan.steps.length>=2; "Parallel-friendly goal should produce multiple steps.")

// -----------------------------------------------------------------
// 2) Validate generated plan
// -----------------------------------------------------------------
var $validText : Text:=$planner.validate_plan({plan: $generated.plan})
var $valid : Object:=JSON Parse($validText)
ASSERT(Bool($valid.success); "Generated plan should validate.")

// -----------------------------------------------------------------
// 3) Validate invalid cyclic plan
// -----------------------------------------------------------------
var $badPlan : Object:={ \
	planId: "pln_bad"; \
	goal: "Bad cycle"; \
	steps: [ \
		{id: "s1"; title: "One"; description: "Step one"; execution: "sequential"; dependsOn: ["s2"]; subAgentProfile: "generalist"; inputs: {}; outputs: ["o1"]}; \
		{id: "s2"; title: "Two"; description: "Step two"; execution: "sequential"; dependsOn: ["s1"]; subAgentProfile: "generalist"; inputs: {}; outputs: ["o2"]} \
	] \
}
var $badText : Text:=$planner.validate_plan({plan: $badPlan})
var $bad : Object:=JSON Parse($badText)
ASSERT(Not(Bool($bad.success)); "Cyclic plan must fail validation.")
ASSERT($bad.errors.length>0; "Cyclic plan validation must provide errors.")

// -----------------------------------------------------------------
// 4) Run plan (sub-agent has no AI client, so step failures are expected)
// -----------------------------------------------------------------
var $runText : Text:=$planner.run_plan({planId: String($generated.plan.planId); executionMode: "parallel"; failureMode: "continue_with_warnings"})
var $run : Object:=JSON Parse($runText)
ASSERT(Length(String($run.planId))>0; "run_plan must return planId.")
ASSERT($run.steps.length>0; "run_plan must return step report.")
ASSERT($run.provenance.subAgentEnabled=True; "run_plan provenance must indicate subAgent tool presence.")

// -----------------------------------------------------------------
// 5) Execute with invalid input
// -----------------------------------------------------------------
var $invalidRun : Object:=JSON Parse($planner.run_plan({}))
ASSERT(Not(Bool($invalidRun.success)); "run_plan without planId/plan must fail.")

ALERT("test_planning passed")
