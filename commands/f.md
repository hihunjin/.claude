---
description: Run this prompt on Fable 5, medium effort
argument-hint: <your prompt>
model: fable
effort: medium
context: fork
background: true
---
$ARGUMENTS

Rules (you are a backgrounded fork; these cover tools you lack):
- Decisions are mine. On ambiguity, real trade-offs, or anything destructive or outward-facing: do the independent work first, then stop and present options. Don't guess and continue.
- Never background a shell command. No TaskOutput, so backgrounded output is unreadable, and Bash backgrounds anything past its 2min timeout. Redirect and read instead: `cmd > /tmp/run.log 2>&1`, then Read it. Or split into sub-2min units. Never use run_in_background.
- No plan mode, but Edit/Write are live. For non-trivial work write the plan to a file first, naming files to touch, then stay in that scope. Out-of-scope work goes in the report, not the tree.
- A denied permission fails only that call; you keep running. Don't retry the goal by another route. Log it under NEEDS DECISION and continue elsewhere.
- End with a report: what you did, what you left out, NEEDS DECISION (or "none").
