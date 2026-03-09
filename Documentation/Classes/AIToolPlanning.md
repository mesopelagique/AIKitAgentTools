# AIToolPlanning

`AIToolPlanning` generates, validates, and executes structured plans.

It supports dependency-aware execution and can use `AIToolSubAgent` for delegated step execution.

## Constructor

```4d
var $sub:=cs.AIToolSubAgent.new({client: $client; toolRegistry: $registry})
var $planning:=cs.AIToolPlanning.new({ \
  client: $client; \
  subAgentTool: $sub; \
  defaultMaxSteps: 8; \
  defaultAllowParallel: False \
})
```

## Plan Schema

```json
{
  "planId": "pln_xxx",
  "goal": "string",
  "steps": [
    {
      "id": "s1",
      "title": "Collect sources",
      "description": "Search and fetch docs",
      "dependsOn": [],
      "execution": "sequential|parallel",
      "subAgentProfile": "researcher",
      "inputs": {},
      "outputs": ["source_notes"]
    }
  ]
}
```

## Tool Functions

### generate_plan({goal, context, maxSteps, allowParallel})

Builds a structured plan and returns it.

### validate_plan({plan})

Validates schema and dependency graph:

- required fields
- duplicate IDs
- unknown dependencies
- dependency cycles

### run_plan({planId|plan, executionMode, failureMode, mergePolicy, reducerPrompt})

Executes plan steps with dependency ordering.

- `executionMode`: `sequential` or `parallel`
- `failureMode`: `fail_fast` or `continue_with_warnings`
- `mergePolicy`: `concat`, `rank`, `vote`, `reducerPrompt`
- `reducerPrompt`: optional reducer instruction used with `mergePolicy = reducerPrompt`

Returns a run report with per-step status, outputs, errors, artifacts, and provenance.

## Notes

- Parallel execution is bounded and deterministic.
- If no sub-agent runtime is available, step execution fails safely with explicit errors.

## See Also

- [AIToolSubAgent](AIToolSubAgent.md)
- [Security Guide](../tools-security.md)
