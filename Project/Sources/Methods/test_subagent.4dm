//%attributes = {}
// test_subagent - Test AIToolSubAgent runtime registry and safety behavior

var $tool:=cs.AIToolSubAgent.new({defaultMaxParallel: 2})

// -----------------------------------------------------------------
// 1) Create sub-agent
// -----------------------------------------------------------------
var $createText : Text:=$tool.subagent_create({ \
	name: "researcher-a"; \
	systemPrompt: "You are a researcher."; \
	allowedTools: ["duckduckgo_search"; "web_fetch"]; \
	model: "gpt-4o-mini" \
})
var $create : Object:=JSON Parse($createText)
ASSERT(Bool($create.success); "subagent_create must succeed.")
ASSERT(Length(String($create.agentId))>0; "subagent_create must return agentId.")

var $agentId : Text:=String($create.agentId)

// -----------------------------------------------------------------
// 2) List agents
// -----------------------------------------------------------------
var $listText : Text:=$tool.subagent_list({})
var $listObj : Object:=JSON Parse($listText)
ASSERT(Bool($listObj.success); "subagent_list must succeed.")
ASSERT($listObj.agents.length>=1; "subagent_list must include created agent.")

// -----------------------------------------------------------------
// 3) Run without AI client configured -> safe failure
// -----------------------------------------------------------------
var $runText : Text:=$tool.subagent_run({agentId: $agentId; task: "summarize the docs"})
var $runObj : Object:=JSON Parse($runText)
ASSERT(Not(Bool($runObj.success)); "subagent_run should fail without configured AI client.")
ASSERT(Length(String($runObj.runId))>0; "subagent_run failure must still produce runId.")

// -----------------------------------------------------------------
// 4) Get run result
// -----------------------------------------------------------------
var $getText : Text:=$tool.subagent_get_result({runId: String($runObj.runId)})
var $getObj : Object:=JSON Parse($getText)
ASSERT(Bool($getObj.success); "subagent_get_result must succeed for known run.")
ASSERT(String($getObj.run.id)=String($runObj.runId); "Returned run id must match.")

// -----------------------------------------------------------------
// 5) Batch run deterministic mode
// -----------------------------------------------------------------
var $batchText : Text:=$tool.subagent_run_batch({ \
	runs: [ \
		{agentId: $agentId; task: "task 1"}; \
		{agentId: $agentId; task: "task 2"} \
	]; \
	maxParallel: 2 \
})
var $batch : Object:=JSON Parse($batchText)
ASSERT(Bool($batch.success); "subagent_run_batch should return success envelope.")
ASSERT(String($batch.executedMode)="sequential_deterministic"; "Batch mode must be deterministic in this implementation.")
ASSERT($batch.results.length=2; "Batch should return two results.")
ASSERT($batch.merged#Null; "Batch response should include merged output envelope.")
ASSERT(String($batch.merged.strategy)="concat"; "Default merge strategy should be concat.")

// Merge strategy correctness checks with synthetic completed outputs
var $sampleResults : Collection:=[ \
	{status: "completed"; output: "alpha"}; \
	{status: "completed"; output: "alpha"}; \
	{status: "completed"; output: "beta and longer"} \
]
var $voteMerged : Object:=$tool._mergeBatchResults($sampleResults; "vote"; "")
ASSERT(String($voteMerged.output)="alpha"; "Vote strategy should return majority output.")

var $rankMerged : Object:=$tool._mergeBatchResults($sampleResults; "rank"; "")
ASSERT(String($rankMerged.output)="beta and longer"; "Rank strategy should select the longest output in deterministic mode.")

var $concatMerged : Object:=$tool._mergeBatchResults($sampleResults; "concat"; "")
ASSERT(Position("alpha"; String($concatMerged.output))>0; "Concat strategy should include all outputs.")

// -----------------------------------------------------------------
// 6) Close agent
// -----------------------------------------------------------------
var $closeText : Text:=$tool.subagent_close({agentId: $agentId})
var $close : Object:=JSON Parse($closeText)
ASSERT(Bool($close.success); "subagent_close must succeed.")

var $runAfterClose : Object:=JSON Parse($tool.subagent_run({agentId: $agentId; task: "should fail"}))
ASSERT(Not(Bool($runAfterClose.success)); "Closed agent must not execute.")

ALERT("test_subagent passed")
