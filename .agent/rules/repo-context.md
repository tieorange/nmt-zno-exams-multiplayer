---
description: Always load repository context before working in this workspace.
alwaysApply: true
---

# Repository Context

For any task in this workspace, read `./AGENTS.md` before planning, editing, or running project-specific commands.

Treat `./AGENTS.md` as the authoritative repository context for:
- architecture and feature boundaries
- backend and frontend conventions
- game security invariants
- logging and error-handling patterns
- required commands and validation steps

If `./AGENTS.md` conflicts with this rule, prefer `./AGENTS.md` for repository-specific guidance.

Critical reminders:
- Preserve clean architecture with feature-based separation.
- Backend is the sole game authority for timers, scoring, answer validation, and correct-answer secrecy.
- UI strings are Ukrainian. Code, comments, and logs are English.
- `data-set/` is read-only.
- Prefer project Make targets for setup and validation.
- Run `make lint` before finalizing code changes when feasible.

If `./AGENTS.md` cannot be read, say that explicitly before proceeding.
