# ROADMAP

This file tracks implementation jobs for AI tools and security controls.

## Global Rules

- Tool class naming: `AIToolXxx` in `Project/Sources/Classes/`.
- Add matching tests: `test_xxx` in `Project/Sources/Methods/` and register in `Project/Sources/folders.json`.
- Add class documentation in `Documentation/Classes/`.
- Update security notes in `Documentation/tools-security.md`.
- Compile and run tests before considering an item done.
- Remove implemented roadmap items from `README.md` roadmap.

## Status Snapshot

| Item | Status | Priority |
|------|--------|----------|
| Human-in-the-Loop Authorization | Implemented (v2) | P1 |
| Planning | Implemented (v2) | P1 |
| Sub-Agent Orchestration | Implemented (v2) | P1 |
| PTY Command Backend (SystemWorker/PTY) | Implemented (v2) | P2 |
| Gmail / Outlook Mail (NetKit) | Implemented (v2) | P2 |
| Calendar (NetKit) | Planned | P3 |
| Vector Store Conversational Memory | Planned | P3 |
| Vector Store Data Retrieval (RAG) | Planned | P3 |

---

## Implemented v2: Human-in-the-Loop Authorization

### Goal

Require explicit approval for sensitive operations, with one-shot decisions and reusable bounded rules.

### Implemented Classes

- `ApprovalEngine` (policy/service)
- `AIToolApproval` (tool-facing queue/rule operations)

### Integrated Tools

- `AIToolCommand.run_command`
- `AIToolFileSystem.write_file`, `create_directory`, `delete_file`, `move_item`, `copy_file`
- `AIToolMail.send_email`
- `AIToolNotification.send_notification`

### Public API

- `approval_list_pending()`
- `approval_get_request({requestId})`
- `approval_decide({requestId, decision, saveRule, ruleScope, ttlSeconds, maxUses, matcher})`
- `approval_list_rules({scope, tool, action})`
- `approval_delete_rule({ruleId})`

### Decision Model

1. Normalize operation payload.
2. Evaluate matching deny rules first.
3. Evaluate allow rules.
4. If no match: return `pending_approval` with `requestId` and fingerprint.
5. On decision, create one-shot fingerprint-bound rule.
6. Optionally persist reusable rule (`scope`, `ttlSeconds`, `maxUses`).

### Persistence

- ORDA mode when `AgentApprovalRule` and `AgentApprovalRequest` dataclasses exist.
- In-memory fallback otherwise.

### Security Controls

- Deny-first precedence.
- Structured matcher fields: `tool/action/targetType/targetPattern/argConstraints`.
- Bounded reusable approvals with TTL and max uses.
- Fingerprint binding to reduce replay/tampering risk.

### Tests

- `test_approval` covers pending flow, allow-once, saved rule behavior, deny precedence, fingerprint mismatch, TTL expiry, rule deletion.

---

## Implemented v2: Planning + Sub-Agent Orchestration

### Goal

Generate and execute dependency-aware plans, with optional child-agent delegation and bounded parallelism.

### Implemented Classes

- `AIToolPlanning`
- `AIToolSubAgent`

### Planning API

- `generate_plan({goal, context, maxSteps, allowParallel})`
- `validate_plan({plan})`
- `run_plan({planId|plan, executionMode, failureMode})`

### Plan Schema (Implemented)

- `planId`, `goal`, `steps[]`
- each step contains `id`, `title`, `description`, `dependsOn[]`, `execution`, `subAgentProfile`, `inputs`, `outputs`

### Sub-Agent API

- `subagent_create({name, systemPrompt, allowedTools, model, limits})`
- `subagent_run({agentId, task, input, timeoutSec})`
- `subagent_run_batch({runs, maxParallel})`
- `subagent_get_result({runId})`
- `subagent_list()`
- `subagent_close({agentId})`

### Execution Model

- DAG validation before execution.
- Ready steps can run in sequential or parallel waves.
- Failure strategy supported: `fail_fast` or `continue_with_warnings`.
- Deterministic report envelope: step statuses, artifacts, provenance.

### Isolation/Safety

- Explicit child-tool allowlists.
- Nested sub-agent creation disabled by default.
- Bounded defaults: `maxParallel=2`, `maxToolCalls=8`, `timeoutSec=60`, token cap.

### Tests

- `test_planning` covers generation, validation, cycle detection, and run reporting.
- `test_subagent` covers create/list/run/get/batch/close paths.

---

## Implemented v2: PTY Backend in AIToolCommand

### Goal

Allow `AIToolCommand` to run through PTY when available while keeping safe fallback to `4D.SystemWorker`.

### Implemented Class/Methods

- Extended class: `AIToolCommand`
- Tool method: `run_command`
- Backend controls:
  - `executionBackend: "auto" | "pty" | "systemworker"`
  - `forceSystemWorker: True|False`
  - per-call override: `run_command({command; backend})`

### Technical Details

- Detect PTY plugin availability via:

```4d
ARRAY TEXT($pluginIndexes; 0x0)
ARRAY TEXT($pluginNames; 0x0)
PLUGIN LIST($pluginIndexes; $pluginNames)
```

- Compile safely even when plugin is missing by using dynamic formula calls:

```4d
Formula from string("PTY Create").call(This; $shell; $cols; $rows; $cwd)
```

### Security And Abuse Controls

- Existing command whitelist still mandatory.
- Existing metacharacter blocking remains enforced before backend execution.
- ApprovalEngine gate remains on `run_command` (independent of backend).
- PTY request falls back to `SystemWorker` when plugin is unavailable.

### Tests

- Added `test_command_backend`: forced SystemWorker, auto mode, PTY request with fallback/no-fallback assertions, and security regressions.

---

## Implemented v2: Gmail / Outlook Mail (4D NetKit)

### Goal

Support provider-aware sending (SMTP, Gmail, Outlook) while preserving existing SMTP behavior.

### Inputs/Dependencies

- Dependency already declared: 4D NetKit.
- Reference source: `/Users/eric/git/GitHub/4D-NetKit`.

### Implemented Class/Methods

- Extended `AIToolMail` with provider mode:
  - `provider`: `smtp` (default), `gmail`, `outlook`
  - `send_email` now dispatches to SMTP or NetKit provider mail senders
  - `check_email_connection` now reports provider readiness for SMTP/NetKit
- Added dynamic NetKit resolution with graceful fallback when NetKit is unavailable.

### Security

- Recipient domain allowlist.
- Per-send caps (recipients, subject/body).
- Provider rate limiting.
- ApprovalEngine gate before send in production profiles.

### Tests

- Added `test_mail_netkit` (network-safe provider wiring and validation checks).
- Existing `test_mail` keeps SMTP and validation regression coverage.

---

## Planned: Calendar (4D NetKit)

### Goal

Read and modify calendar events for Google and Microsoft providers.

### Class/Methods

- Class: `AIToolCalendar`
- Methods:
  - `list_events`
  - `create_event`
  - `update_event`
  - `delete_event`
  - optional `find_free_slots`

### Data/Behavior Requirements

- Normalized event schema across providers.
- Mandatory timezone handling in inputs/outputs.
- Provider-specific fields isolated in `metadata`.

### Security

- Calendar ID allowlist for write actions.
- Query date-range limits.
- Approval gate for create/update/delete operations.

### Tests

- `test_calendar` with provider stubs and timezone assertions.

---

## Planned: Vector Store Conversational Memory

### Goal

Persist/retrieve semantically relevant conversation snippets beyond token window.

### Storage Model

- Vectors stored as `4D.Vector` in object fields.
- Default embeddings via OpenAI client.
- Optional alternate backend via formula injection.

### Class/Methods

- Class: `AIToolVectorMemory`
- Methods:
  - `memory_store_vector`
  - `memory_retrieve_vector`
  - `memory_delete_vector`
  - optional `memory_compact`

### Retrieval Behavior

- Query by minimum similarity percent.
- Sort descending by similarity.
- Apply application-level top limit.

### Security/Operations

- Per-user isolation keys.
- Retention policy for sensitive content.
- Entry and payload caps.

### Tests

- `test_vector_memory` for store/retrieve/delete, custom embedding formula path, ordering and thresholds.

---

## Planned: Vector Store Data Retrieval (RAG)

### Goal

Retrieve dataclass records using semantic similarity to support question answering.

### Storage Model

- Use `4D.Vector` fields in indexed dataclasses.
- Similarity is returned as percent; top-N handled in app logic.

### Class/Methods

- Class: `AIToolRAGData`
- Methods:
  - `index_dataclass_vectors`
  - `search_dataclass_vectors`
  - `refresh_vector_index`

### Security

- Dataclass and attribute allowlists.
- Prompt injection-safe answer synthesis flow.
- Query limits and audit logging.

### Tests

- `test_rag_data` for indexing, semantic search ranking, filters, and failure paths.

---

## Rollout Guidance

1. Keep approvals enforce-enabled for command and destructive filesystem actions.
2. Extend enforcement to mail/notification and keep command approvals enforced regardless of SystemWorker/PTY backend.
3. Keep conservative parallel defaults (`maxParallel=2`) for sub-agent runs.
4. Maintain structured audit logs for approvals and plan/sub-agent execution traces.
