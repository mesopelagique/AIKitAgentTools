# AGENTS.md

This file is the source of truth for agent instructions in this repository.

## Add or Edit a Tool

When adding a new tool (or making significant changes to an existing one):

1. Create or update the tool class in `Project/Sources/Classes/` using the `AIToolXXX` naming pattern (example: `AIToolCalendar`).
2. Add or update a matching test method in `Project/Sources/Methods/` using the `test_xxx` naming pattern (example: `test_calendar`).
3. Register the `test_xxx` method in `Project/Sources/folders.json` under `"tests" > "methods"`.
4. Document the tool class in `Documentation/Classes/` (one markdown file per tool class).
5. Describe possible security issues for the tool.
6. Describe possible overuse/cost risks for the tool.
7. Update `Documentation/tools-security.md` accordingly.
8. Compile and test before considering the change complete.

## Compile and Test Workflow

If available, use the skills:
- `/4d-check-syntax`
- `/4d-run`

These skills originally come from [e-marchand/skills](https://github.com/e-marchand/skills).

Typical checks:

1. Run syntax/compile checks (`/4d-check-syntax`).
2. Run the relevant `test_xxx` method(s) (`/4d-run`).
3. Fix issues and re-run until green.

## Roadmap Hygiene

If a roadmap item is implemented, remove it from `README.md` (`Roadmap — Future Tools` section).
