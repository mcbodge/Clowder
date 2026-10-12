---
description: 'Lean, surgical coding: the smallest correct change, reuse before writing, no speculative code, every changed line traceable to the task (adapted from Ponytail and the Karpathy guidelines)'
applyTo: '**/*.cs, **/*.razor, **/*.ts, **/*.tsx, **/*.js, **/*.jsx, **/*.py, **/*.ps1, **/*.sh, **/*.sql'
---

# Lean code

Understand the problem first: read the task and the code it touches, trace the real flow end to end, and list every place the change must reach (callers, tests, fixtures, config, exports) and what it could break (data it destroys or exposes, callers that stop working). State your assumptions; when the request has several plausible readings, ask (as a subagent, return the question as a blocker) instead of picking one silently, and say so when a simpler approach exists. Define the check that proves success (a failing test, a command, a Playwright flow) before changing code, and loop until it passes. Then stop at the first rung that holds:
1. Does it need to be built at all? Name in one line anything you skip.
2. Does this codebase already have it? Reuse the helper or pattern the way the surrounding code does.
3. Do the standard library or the platform already do it?
4. Does an installed dependency already do it? Never add one a few lines can replace.
5. Only then write the minimum code that works, or one line when a reader gets it at a glance.

- Be lazy about the solution, not about the change: once you know everything it touches, finish every part the task needs, including the callers, tests, and fixtures your change breaks.
- Fix bugs at the root: check every caller of the code you change and fix the shared code once, not one caller at a time. Code you move or merge keeps its error handling and validation.
- No abstraction, wrapper, type conversion, option, or boilerplate nobody asked for; no handling for cases that can't happen; keep values in the form the platform already gives you.
- Deletion over addition, boring over clever, fewest files possible. The shortest correct diff wins, yet a one-liner a reader must decode is not short; the smallest change in the wrong place is a second bug. If a senior engineer would call it overcomplicated, simplify it.
- Surgical edits: every changed line traces to the task. Don't reformat, rename, or "improve" adjacent code; match the local style and the codebase's layers and interfaces; comment only the why the code cannot show, in one line; mention unrelated dead code instead of deleting it; remove only the imports, variables, and functions your change made unused.
- When two approaches cost the same, pick the one that handles edge cases correctly. A deliberate shortcut with a known limit (naive algorithm, coarse lock) gets a one-line `shortcut: <limit>, <when to upgrade>` comment.
- Never cut corners on understanding the problem, input validation at trust boundaries, error handling that prevents data loss, security, accessibility, or anything explicitly requested. New non-trivial logic (a branch, a loop, a parser, money, security, or a new script) leaves one small test or an assert-based self-check; trivial changes need none.
