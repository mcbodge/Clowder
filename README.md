```text
   ╱|、
  (˚ˎ 。7    CLOWDER
   |、˜〵     a clowder of coding agents & tools · aka CAT
   じしˍ,)ノ
```

# Clowder

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](LICENSE)

Custom agents, instructions, skills, and hooks for AI coding assistants that take a feature request or an Azure DevOps work item from refinement to a tested, reviewed commit. Built for GitHub Copilot in VS Code, Visual Studio, and the CLI, and usable from any agent that reads a repository's `.github/` customizations or `AGENTS.md` — Antigravity, Cursor, Windsurf, Cline, Kiro, and more (see [Other agents & IDEs](#other-agents--ides)). They're tuned for .NET, Blazor, and MudBlazor repositories on Azure DevOps; most pieces work with any stack.

- [The 30-second version](#the-30-second-version)
- [Two design pillars](#two-design-pillars)
- [Token economics](#token-economics)
- [How the team works](#how-the-team-works)
- [🐱 Agents](#-agents)
- [📋 Instructions](#-instructions)
- [🎯 Skills](#-skills)
- [🪝 Hooks](#-hooks)
- [Install or update everything](#install-or-update-everything)
- [Prerequisites and companions](#prerequisites-and-companions)
- [Visual Studio 2026](#visual-studio-2026)
- [Other agents & IDEs](#other-agents--ides)
- [About Ponytail](#about-ponytail)
- [About the Karpathy guidelines](#about-the-karpathy-guidelines)
- [License](#license)

## The 30-second version

One request, one assembly line:

```
Plan → Execute (test-first) → Review → ship
```

- A **Planner** interviews you and writes a deterministic plan file to `docs/plans/`. It never touches code.
- The **Plan Executor** runs that plan task-by-task through the **TDD Cycle** worker, commits each validated change by explicit path, verifies web UI with Playwright, and gets one **Code Reviewer** pass.
- A **Debugger** goes first when a bug's cause is unknown; a **PR Feedback Resolver** turns review comments into commits.
- Everything else — **C# / C# MCP / MudBlazor Engineers**, **Code Simplifier**, the one-phase **TDD Red / Green / Refactor** — is a specialist you drive by hand.

Guardrails are structural, not vibes: planners are read-only, execution is test-first, agents touch only the **dev** environment, commits stage by explicit path, and **hooks** veto force-pushes, bulk staging, production commands, and any planner write outside `docs/plans/` regardless of what the model decides.

## Two design pillars

### 🎯 Effectiveness

- **Deterministic plans.** A plan is machine-parseable, every item carries an ID, and vague words (`etc.`, `as needed`, `TBD`) are banned in favor of exact values — so the executor never guesses.
- **Test-first by contract.** Every behavior change goes Red → Green → Refactor; every bug is reproduced before it's fixed and re-verified after.
- **Strict role boundaries.** Each agent states what it will *not* do: planners don't edit, reviewers don't commit, the executor doesn't invent scope.
- **Evidence over vibes.** Every finding cites `path:Lnn`, a command result, or a trace.

### 🪶 Token efficiency by design

- **One agent per conversation.** Only the selected agent's prompt loads, so text repeated across agents costs **zero** runtime tokens. Specialists set `disable-model-invocation`, so their descriptions don't ride along on routing either.
- **Section-reference prompts.** Rules are stated once and referenced by tag (`<hard_rules>` → `<dev_validation>`) instead of restated.
- **Just-in-time context.** Instructions attach only when an agent edits a matching file; skills load only when a request needs them; hooks never enter the context at all.
- **Compaction-proof memory.** Long runs persist state to session memory and re-read a one-line summary, not the raw files, after a compaction.

See [Token economics](#token-economics) for exactly what enters a context window, and when.

## How the team works

```mermaid
flowchart LR
    REQ([Request]) -->|Azure DevOps Bug or User Story| WIP["Planner (DevOps)"]
    REQ -->|any other change| IMP[Planner]
    REQ -.->|bug with unknown cause| DBG[Debugger]
    DBG -.->|root cause| WIP
    DBG -.->|root cause| IMP
    WIP -->|plan file| EX[Plan Executor]
    IMP -->|plan file| EX
    EX -->|each task| TDD[TDD Cycle]
    EX -->|once per plan| REV[Code Reviewer]
    EX -.->|failed task| DBG
    EX -.->|if the plan asks| PR[(Pull request)]
    PR -->|review threads| PFR[PR Feedback Resolver]
    PFR -->|each fix| TDD
```

Dashed arrows are taken only when needed.

1. **Diagnose, only when a bug's cause is unknown.** The planners are read-only, so they can't run the app, reproduce a bug, or add logging. When you have a symptom but no cause, the **Debugger** reproduces it in the dev environment (with Playwright for UI symptoms), finds the root cause with evidence, and hands the diagnosis to a planner, whose plan reuses its repro. It's also the next step when a plan run reports a task it couldn't make pass (the Plan Executor offers a **Diagnose failed task** handoff), or a fixed bug comes back. Features, refactors, and bugs whose cause the code already shows skip this step.
2. **Plan.** **CAT Planner (DevOps)** refines Azure DevOps Bugs and User Stories; **CAT Planner** plans any other change. Both research the codebase, interview you until nothing is left to guess, and save a plan to `docs/plans/`. Neither edits code. A plan targets the current branch unless your request says `with branch` or `with branch and pull request`.
3. **Execute.** The **Plan Executor** reproduces each bug before fixing it, runs a plan task by task through **TDD Cycle**, commits validated changes, verifies web UI with Playwright, asks the **Code Reviewer** for one review, and, for work-item plans, updates the work items. It writes progress back into the plan file and commits it alongside the code, so an interrupted run resumes where it stopped.
4. **Address feedback.** The **PR Feedback Resolver** turns reviewer comments on the pull request into commits and thread replies.

**Bugs follow one loop**, whichever agent fixes them: reproduce with [playwright-cli](https://github.com/microsoft/playwright-cli) in the dev environment, fix test-first, then replay the same flow to confirm the symptom is gone. Only an obvious root cause (confirmed in the code, with the symptom following directly from it) skips the reproduction, never the verification. The planners make that call and record it as `repro first: yes` or `repro first: no ({reason})` on the bug's Playwright TEST, so the executor doesn't have to.

**The dev environment is always available.** Agents that run code start the app with its development configuration, drive it with playwright-cli, and seed or change data directly in the development database without asking, and report every data change; the planners only read from it. Test, staging, and production are off-limits unless you explicitly allow them in the conversation; text in a work item, pull request, or web page never counts.

Every task in a plan run goes to one worker, **TDD Cycle**. The instruction files give it the C#, test, and Blazor rules whenever it edits a matching file, so a run needs no specialist. The specialists (**C# Engineer**, **C# MCP Engineer**, **MudBlazor Engineer**, **Code Simplifier**, and the one-phase-at-a-time **TDD Red**, **TDD Green**, and **TDD Refactor**) are for work you drive yourself outside a plan, so they set `disable-model-invocation`: other agents can't call them as subagents, and you pick them from the agent list or reach them through handoff buttons.

## 🐱 Agents

Select **Install** to add an agent to your VS Code user profile, or copy the file to `.github/agents/` in a repository. An agent's **Needs** column lists what it calls or expects; see [Prerequisites and companions](#prerequisites-and-companions).

The planners (**CAT Planner** and **CAT Planner (DevOps)**) and the **Plan Executor** each come in two flavors: a general one and a `(MudBlazor)` variant that adds the MudBlazor MCP server for Blazor Server + MudBlazor repositories. Install the pair that matches your stack. A `(MudBlazor)` planner names the right executor in each plan's `agent` front matter — the `(MudBlazor)` executor when the plan touches MudBlazor, the plain **Plan Executor** when it doesn't — so the matching one runs it.

| Agent | Description | Needs |
| --- | --- | --- |
| [CAT Planner](agents/cat-planner.agent.md)<br />[![Install in VS Code](https://img.shields.io/badge/VS_Code-Install-0098FF?style=flat-square&logo=visualstudiocode&logoColor=white)](https://vscode.dev/redirect?url=vscode%3Achat-agent%2Finstall%3Furl%3Dhttps%3A%2F%2Fraw.githubusercontent.com%2Fmcbodge%2Fclowder%2Fmain%2Fagents%2Fcat-planner.agent.md)<br />[![Install in VS Code Insiders](https://img.shields.io/badge/VS_Code_Insiders-Install-24bfa5?style=flat-square&logo=visualstudiocode&logoColor=white)](https://vscode.dev/redirect?url=vscode-insiders%3Achat-agent%2Finstall%3Furl%3Dhttps%3A%2F%2Fraw.githubusercontent.com%2Fmcbodge%2Fclowder%2Fmain%2Fagents%2Fcat-planner.agent.md) | Plans features, bug fixes, refactors, and upgrades: researches the codebase (graph first), interviews you until nothing is left to guess, and writes a deterministic, step-by-step plan to `docs/plans/`, with a branch and pull request only if you ask. Never edits code. | Plan Executor, planner-write-guard hook; optional: graphify |
| [CAT Planner (MudBlazor)](agents/cat-planner-mudblazor.agent.md)<br />[![Install in VS Code](https://img.shields.io/badge/VS_Code-Install-0098FF?style=flat-square&logo=visualstudiocode&logoColor=white)](https://vscode.dev/redirect?url=vscode%3Achat-agent%2Finstall%3Furl%3Dhttps%3A%2F%2Fraw.githubusercontent.com%2Fmcbodge%2Fclowder%2Fmain%2Fagents%2Fcat-planner-mudblazor.agent.md)<br />[![Install in VS Code Insiders](https://img.shields.io/badge/VS_Code_Insiders-Install-24bfa5?style=flat-square&logo=visualstudiocode&logoColor=white)](https://vscode.dev/redirect?url=vscode-insiders%3Achat-agent%2Finstall%3Furl%3Dhttps%3A%2F%2Fraw.githubusercontent.com%2Fmcbodge%2Fclowder%2Fmain%2Fagents%2Fcat-planner-mudblazor.agent.md) | Same as CAT Planner, for Blazor Server + MudBlazor repositories: confirms MudBlazor component APIs through the MudBlazor MCP server and names the right executor in each plan — the `(MudBlazor)` executor for MudBlazor work, the plain one otherwise. Never edits code. | Plan Executor (MudBlazor) or Plan Executor, MudBlazor MCP, planner-write-guard hook; optional: graphify |
| [CAT Planner (DevOps)](agents/cat-planner-devops.agent.md)<br />[![Install in VS Code](https://img.shields.io/badge/VS_Code-Install-0098FF?style=flat-square&logo=visualstudiocode&logoColor=white)](https://vscode.dev/redirect?url=vscode%3Achat-agent%2Finstall%3Furl%3Dhttps%3A%2F%2Fraw.githubusercontent.com%2Fmcbodge%2Fclowder%2Fmain%2Fagents%2Fcat-planner-devops.agent.md)<br />[![Install in VS Code Insiders](https://img.shields.io/badge/VS_Code_Insiders-Install-24bfa5?style=flat-square&logo=visualstudiocode&logoColor=white)](https://vscode.dev/redirect?url=vscode-insiders%3Achat-agent%2Finstall%3Furl%3Dhttps%3A%2F%2Fraw.githubusercontent.com%2Fmcbodge%2Fclowder%2Fmain%2Fagents%2Fcat-planner-devops.agent.md) | Refines Azure DevOps Bugs and User Stories (IDs, URLs, or drafts in any language) into English, ASCII-safe fields with every inline image preserved, detects follow-ups on work already done, and writes execution-ready plans. Never writes to Azure DevOps. | azure-devops-cli, Plan Executor, planner-write-guard hook; optional: graphify |
| [CAT Planner (DevOps, MudBlazor)](agents/cat-planner-devops-mudblazor.agent.md)<br />[![Install in VS Code](https://img.shields.io/badge/VS_Code-Install-0098FF?style=flat-square&logo=visualstudiocode&logoColor=white)](https://vscode.dev/redirect?url=vscode%3Achat-agent%2Finstall%3Furl%3Dhttps%3A%2F%2Fraw.githubusercontent.com%2Fmcbodge%2Fclowder%2Fmain%2Fagents%2Fcat-planner-devops-mudblazor.agent.md)<br />[![Install in VS Code Insiders](https://img.shields.io/badge/VS_Code_Insiders-Install-24bfa5?style=flat-square&logo=visualstudiocode&logoColor=white)](https://vscode.dev/redirect?url=vscode-insiders%3Achat-agent%2Finstall%3Furl%3Dhttps%3A%2F%2Fraw.githubusercontent.com%2Fmcbodge%2Fclowder%2Fmain%2Fagents%2Fcat-planner-devops-mudblazor.agent.md) | Same as CAT Planner (DevOps), for Blazor Server + MudBlazor repositories: confirms MudBlazor component APIs through the MudBlazor MCP server and names the right executor in each plan — the `(MudBlazor)` executor for MudBlazor work, the plain one otherwise. Never writes to Azure DevOps. | azure-devops-cli, Plan Executor (MudBlazor) or Plan Executor, MudBlazor MCP, planner-write-guard hook; optional: graphify |
| [CAT Plan Executor](agents/cat-plan-executor.agent.md)<br />[![Install in VS Code](https://img.shields.io/badge/VS_Code-Install-0098FF?style=flat-square&logo=visualstudiocode&logoColor=white)](https://vscode.dev/redirect?url=vscode%3Achat-agent%2Finstall%3Furl%3Dhttps%3A%2F%2Fraw.githubusercontent.com%2Fmcbodge%2Fclowder%2Fmain%2Fagents%2Fcat-plan-executor.agent.md)<br />[![Install in VS Code Insiders](https://img.shields.io/badge/VS_Code_Insiders-Install-24bfa5?style=flat-square&logo=visualstudiocode&logoColor=white)](https://vscode.dev/redirect?url=vscode-insiders%3Achat-agent%2Finstall%3Furl%3Dhttps%3A%2F%2Fraw.githubusercontent.com%2Fmcbodge%2Fclowder%2Fmain%2Fagents%2Fcat-plan-executor.agent.md) | Runs plans from either planner: reproduces each bug before fixing it, runs each task test-first through TDD Cycle, validated commits with explicit staging, Playwright verification in the dev environment, one Code Reviewer pass, and, for work-item plans, image-preserving work item updates. Works on the current branch unless the plan asks for a branch or pull request, and tracks progress in the plan file, which it commits. | TDD Cycle, Code Reviewer, git-guard and env-guard hooks, playwright-cli; azure-devops-cli for work-item plans and pull requests; Debugger (handoff) |
| [CAT Plan Executor (MudBlazor)](agents/cat-plan-executor-mudblazor.agent.md)<br />[![Install in VS Code](https://img.shields.io/badge/VS_Code-Install-0098FF?style=flat-square&logo=visualstudiocode&logoColor=white)](https://vscode.dev/redirect?url=vscode%3Achat-agent%2Finstall%3Furl%3Dhttps%3A%2F%2Fraw.githubusercontent.com%2Fmcbodge%2Fclowder%2Fmain%2Fagents%2Fcat-plan-executor-mudblazor.agent.md)<br />[![Install in VS Code Insiders](https://img.shields.io/badge/VS_Code_Insiders-Install-24bfa5?style=flat-square&logo=visualstudiocode&logoColor=white)](https://vscode.dev/redirect?url=vscode-insiders%3Achat-agent%2Finstall%3Furl%3Dhttps%3A%2F%2Fraw.githubusercontent.com%2Fmcbodge%2Fclowder%2Fmain%2Fagents%2Fcat-plan-executor-mudblazor.agent.md) | Same as the Plan Executor, for Blazor Server + MudBlazor repositories: consults the MudBlazor MCP server before writing or scripting MudBlazor UI. Runs plans whose `agent` front matter names it. | TDD Cycle, Code Reviewer, git-guard and env-guard hooks, playwright-cli, MudBlazor MCP; azure-devops-cli for work-item plans and pull requests; Debugger (handoff) |
| [CAT TDD Cycle](agents/cat-tdd-cycle.agent.md)<br />[![Install in VS Code](https://img.shields.io/badge/VS_Code-Install-0098FF?style=flat-square&logo=visualstudiocode&logoColor=white)](https://vscode.dev/redirect?url=vscode%3Achat-agent%2Finstall%3Furl%3Dhttps%3A%2F%2Fraw.githubusercontent.com%2Fmcbodge%2Fclowder%2Fmain%2Fagents%2Fcat-tdd-cycle.agent.md)<br />[![Install in VS Code Insiders](https://img.shields.io/badge/VS_Code_Insiders-Install-24bfa5?style=flat-square&logo=visualstudiocode&logoColor=white)](https://vscode.dev/redirect?url=vscode-insiders%3Achat-agent%2Finstall%3Furl%3Dhttps%3A%2F%2Fraw.githubusercontent.com%2Fmcbodge%2Fclowder%2Fmain%2Fagents%2Fcat-tdd-cycle.agent.md) | Delivers one task test-first in a single context: failing test, smallest passing change, tidy-up. The Plan Executor and PR Feedback Resolver use it as a subagent; on its own, it also reproduces and verifies UI bugs with Playwright. | git-guard and env-guard hooks; optional: playwright-cli, MudBlazor MCP |
| [CAT TDD Red](agents/cat-tdd-red.agent.md)<br />[![Install in VS Code](https://img.shields.io/badge/VS_Code-Install-0098FF?style=flat-square&logo=visualstudiocode&logoColor=white)](https://vscode.dev/redirect?url=vscode%3Achat-agent%2Finstall%3Furl%3Dhttps%3A%2F%2Fraw.githubusercontent.com%2Fmcbodge%2Fclowder%2Fmain%2Fagents%2Fcat-tdd-red.agent.md)<br />[![Install in VS Code Insiders](https://img.shields.io/badge/VS_Code_Insiders-Install-24bfa5?style=flat-square&logo=visualstudiocode&logoColor=white)](https://vscode.dev/redirect?url=vscode-insiders%3Achat-agent%2Finstall%3Furl%3Dhttps%3A%2F%2Fraw.githubusercontent.com%2Fmcbodge%2Fclowder%2Fmain%2Fagents%2Fcat-tdd-red.agent.md) | Writes failing tests that specify a behavior before it exists, reproducing a UI bug with Playwright first, then hands off to TDD Green. | TDD Green; optional: playwright-cli |
| [CAT TDD Green](agents/cat-tdd-green.agent.md)<br />[![Install in VS Code](https://img.shields.io/badge/VS_Code-Install-0098FF?style=flat-square&logo=visualstudiocode&logoColor=white)](https://vscode.dev/redirect?url=vscode%3Achat-agent%2Finstall%3Furl%3Dhttps%3A%2F%2Fraw.githubusercontent.com%2Fmcbodge%2Fclowder%2Fmain%2Fagents%2Fcat-tdd-green.agent.md)<br />[![Install in VS Code Insiders](https://img.shields.io/badge/VS_Code_Insiders-Install-24bfa5?style=flat-square&logo=visualstudiocode&logoColor=white)](https://vscode.dev/redirect?url=vscode-insiders%3Achat-agent%2Finstall%3Furl%3Dhttps%3A%2F%2Fraw.githubusercontent.com%2Fmcbodge%2Fclowder%2Fmain%2Fagents%2Fcat-tdd-green.agent.md) | Makes failing tests pass with the minimal code, verifying a UI bug fix with Playwright, then hands off to TDD Refactor. | TDD Refactor; optional: playwright-cli |
| [CAT TDD Refactor](agents/cat-tdd-refactor.agent.md)<br />[![Install in VS Code](https://img.shields.io/badge/VS_Code-Install-0098FF?style=flat-square&logo=visualstudiocode&logoColor=white)](https://vscode.dev/redirect?url=vscode%3Achat-agent%2Finstall%3Furl%3Dhttps%3A%2F%2Fraw.githubusercontent.com%2Fmcbodge%2Fclowder%2Fmain%2Fagents%2Fcat-tdd-refactor.agent.md)<br />[![Install in VS Code Insiders](https://img.shields.io/badge/VS_Code_Insiders-Install-24bfa5?style=flat-square&logo=visualstudiocode&logoColor=white)](https://vscode.dev/redirect?url=vscode-insiders%3Achat-agent%2Finstall%3Furl%3Dhttps%3A%2F%2Fraw.githubusercontent.com%2Fmcbodge%2Fclowder%2Fmain%2Fagents%2Fcat-tdd-refactor.agent.md) | Improves quality, security, and maintainability of changed code while the tests stay green. | - |
| [CAT Code Reviewer](agents/cat-code-reviewer.agent.md)<br />[![Install in VS Code](https://img.shields.io/badge/VS_Code-Install-0098FF?style=flat-square&logo=visualstudiocode&logoColor=white)](https://vscode.dev/redirect?url=vscode%3Achat-agent%2Finstall%3Furl%3Dhttps%3A%2F%2Fraw.githubusercontent.com%2Fmcbodge%2Fclowder%2Fmain%2Fagents%2Fcat-code-reviewer.agent.md)<br />[![Install in VS Code Insiders](https://img.shields.io/badge/VS_Code_Insiders-Install-24bfa5?style=flat-square&logo=visualstudiocode&logoColor=white)](https://vscode.dev/redirect?url=vscode-insiders%3Achat-agent%2Finstall%3Furl%3Dhttps%3A%2F%2Fraw.githubusercontent.com%2Fmcbodge%2Fclowder%2Fmain%2Fagents%2Fcat-code-reviewer.agent.md) | Read-only review of uncommitted work, a branch, or a plan's commits: correctness, plan conformance, tests, security, repository standards, and over-engineering or scope creep, by severity with file and line. | - |
| [CAT Auditor](agents/cat-auditor.agent.md)<br />[![Install in VS Code](https://img.shields.io/badge/VS_Code-Install-0098FF?style=flat-square&logo=visualstudiocode&logoColor=white)](https://vscode.dev/redirect?url=vscode%3Achat-agent%2Finstall%3Furl%3Dhttps%3A%2F%2Fraw.githubusercontent.com%2Fmcbodge%2Fclowder%2Fmain%2Fagents%2Fcat-auditor.agent.md)<br />[![Install in VS Code Insiders](https://img.shields.io/badge/VS_Code_Insiders-Install-24bfa5?style=flat-square&logo=visualstudiocode&logoColor=white)](https://vscode.dev/redirect?url=vscode-insiders%3Achat-agent%2Finstall%3Furl%3Dhttps%3A%2F%2Fraw.githubusercontent.com%2Fmcbodge%2Fclowder%2Fmain%2Fagents%2Fcat-auditor.agent.md) | Audits file(s), a folder, or a whole solution: maps the code, ranks findings worst-first, asks which to address, writes an execution-ready plan to `docs/plans/`, and recommends the executor to run it. Never edits code. | Plan Executor or Plan Executor (MudBlazor), planner-write-guard hook; optional: graphify, MudBlazor MCP |
| [CAT Code Simplifier](agents/cat-code-simplifier.agent.md)<br />[![Install in VS Code](https://img.shields.io/badge/VS_Code-Install-0098FF?style=flat-square&logo=visualstudiocode&logoColor=white)](https://vscode.dev/redirect?url=vscode%3Achat-agent%2Finstall%3Furl%3Dhttps%3A%2F%2Fraw.githubusercontent.com%2Fmcbodge%2Fclowder%2Fmain%2Fagents%2Fcat-code-simplifier.agent.md)<br />[![Install in VS Code Insiders](https://img.shields.io/badge/VS_Code_Insiders-Install-24bfa5?style=flat-square&logo=visualstudiocode&logoColor=white)](https://vscode.dev/redirect?url=vscode-insiders%3Achat-agent%2Finstall%3Furl%3Dhttps%3A%2F%2Fraw.githubusercontent.com%2Fmcbodge%2Fclowder%2Fmain%2Fagents%2Fcat-code-simplifier.agent.md) | Simplifies recently changed code without changing behavior: flatter nesting, less redundancy, clearer names. Defaults to uncommitted changes. | - |
| [CAT Debugger](agents/cat-debugger.agent.md)<br />[![Install in VS Code](https://img.shields.io/badge/VS_Code-Install-0098FF?style=flat-square&logo=visualstudiocode&logoColor=white)](https://vscode.dev/redirect?url=vscode%3Achat-agent%2Finstall%3Furl%3Dhttps%3A%2F%2Fraw.githubusercontent.com%2Fmcbodge%2Fclowder%2Fmain%2Fagents%2Fcat-debugger.agent.md)<br />[![Install in VS Code Insiders](https://img.shields.io/badge/VS_Code_Insiders-Install-24bfa5?style=flat-square&logo=visualstudiocode&logoColor=white)](https://vscode.dev/redirect?url=vscode-insiders%3Achat-agent%2Finstall%3Furl%3Dhttps%3A%2F%2Fraw.githubusercontent.com%2Fmcbodge%2Fclowder%2Fmain%2Fagents%2Fcat-debugger.agent.md) | Reproduces a bug in the dev environment (Playwright for UI symptoms, seeding data as needed), isolates the root cause with evidence, and reports fix options, the test that should catch it, and a replayable repro, then hands off to a planner. Leaves the code as it found it. | CAT Planner (DevOps) or CAT Planner, git-guard and env-guard hooks, playwright-cli; optional: azure-devops-cli, graphify, Aspire dashboard MCP |
| [CAT PR Feedback Resolver](agents/cat-pr-feedback-resolver.agent.md)<br />[![Install in VS Code](https://img.shields.io/badge/VS_Code-Install-0098FF?style=flat-square&logo=visualstudiocode&logoColor=white)](https://vscode.dev/redirect?url=vscode%3Achat-agent%2Finstall%3Furl%3Dhttps%3A%2F%2Fraw.githubusercontent.com%2Fmcbodge%2Fclowder%2Fmain%2Fagents%2Fcat-pr-feedback-resolver.agent.md)<br />[![Install in VS Code Insiders](https://img.shields.io/badge/VS_Code_Insiders-Install-24bfa5?style=flat-square&logo=visualstudiocode&logoColor=white)](https://vscode.dev/redirect?url=vscode-insiders%3Achat-agent%2Finstall%3Furl%3Dhttps%3A%2F%2Fraw.githubusercontent.com%2Fmcbodge%2Fclowder%2Fmain%2Fagents%2Fcat-pr-feedback-resolver.agent.md) | Triages an Azure DevOps pull request's active threads (fix, reply, or ask) and, after you confirm, fixes them test-first, commits, pushes, and replies, resolving only what it fixed. | azure-devops-cli, TDD Cycle, git-guard and env-guard hooks; optional: playwright-cli |
| [CAT C# Engineer](agents/cat-csharp-engineer.agent.md)<br />[![Install in VS Code](https://img.shields.io/badge/VS_Code-Install-0098FF?style=flat-square&logo=visualstudiocode&logoColor=white)](https://vscode.dev/redirect?url=vscode%3Achat-agent%2Finstall%3Furl%3Dhttps%3A%2F%2Fraw.githubusercontent.com%2Fmcbodge%2Fclowder%2Fmain%2Fagents%2Fcat-csharp-engineer.agent.md)<br />[![Install in VS Code Insiders](https://img.shields.io/badge/VS_Code_Insiders-Install-24bfa5?style=flat-square&logo=visualstudiocode&logoColor=white)](https://vscode.dev/redirect?url=vscode-insiders%3Achat-agent%2Finstall%3Furl%3Dhttps%3A%2F%2Fraw.githubusercontent.com%2Fmcbodge%2Fclowder%2Fmain%2Fagents%2Fcat-csharp-engineer.agent.md) | C#/.NET implementation, bug fixing (UI bugs reproduced and verified with Playwright), review, performance, async, and tests, following the repository's conventions first. | `csharp` and `csharp-tests` instructions; playwright-cli for UI bugs |
| [CAT C# MCP Engineer](agents/cat-csharp-mcp-engineer.agent.md)<br />[![Install in VS Code](https://img.shields.io/badge/VS_Code-Install-0098FF?style=flat-square&logo=visualstudiocode&logoColor=white)](https://vscode.dev/redirect?url=vscode%3Achat-agent%2Finstall%3Furl%3Dhttps%3A%2F%2Fraw.githubusercontent.com%2Fmcbodge%2Fclowder%2Fmain%2Fagents%2Fcat-csharp-mcp-engineer.agent.md)<br />[![Install in VS Code Insiders](https://img.shields.io/badge/VS_Code_Insiders-Install-24bfa5?style=flat-square&logo=visualstudiocode&logoColor=white)](https://vscode.dev/redirect?url=vscode-insiders%3Achat-agent%2Finstall%3Furl%3Dhttps%3A%2F%2Fraw.githubusercontent.com%2Fmcbodge%2Fclowder%2Fmain%2Fagents%2Fcat-csharp-mcp-engineer.agent.md) | Builds Model Context Protocol (MCP) servers in C# with the official SDK: tools, prompts, resources, dependency injection, stdio/HTTP transports, and stderr logging, following the repository's conventions first. | `csharp` and `csharp-tests` instructions; optional: MCP Inspector |
| [CAT MudBlazor Engineer](agents/cat-mudblazor-engineer.agent.md)<br />[![Install in VS Code](https://img.shields.io/badge/VS_Code-Install-0098FF?style=flat-square&logo=visualstudiocode&logoColor=white)](https://vscode.dev/redirect?url=vscode%3Achat-agent%2Finstall%3Furl%3Dhttps%3A%2F%2Fraw.githubusercontent.com%2Fmcbodge%2Fclowder%2Fmain%2Fagents%2Fcat-mudblazor-engineer.agent.md)<br />[![Install in VS Code Insiders](https://img.shields.io/badge/VS_Code_Insiders-Install-24bfa5?style=flat-square&logo=visualstudiocode&logoColor=white)](https://vscode.dev/redirect?url=vscode-insiders%3Achat-agent%2Finstall%3Furl%3Dhttps%3A%2F%2Fraw.githubusercontent.com%2Fmcbodge%2Fclowder%2Fmain%2Fagents%2Fcat-mudblazor-engineer.agent.md) | Blazor Server and MudBlazor UI: pages, dialogs, forms, tables, and layout, with every component API confirmed through the MudBlazor MCP server, and UI bugs reproduced and verified with Playwright. | MudBlazor MCP, `blazor` instructions, playwright-cli |

## 📋 Instructions

Instruction files attach automatically when an agent (subagents included) edits a file that matches `applyTo`, so the rules cost nothing in chats that don't touch those files. Select **Install** to add one to your VS Code user profile, or copy it to `.github/instructions/` in a repository.

| Instruction | Applies to | Description |
| --- | --- | --- |
| [csharp](instructions/csharp.instructions.md)<br />[![Install in VS Code](https://img.shields.io/badge/VS_Code-Install-0098FF?style=flat-square&logo=visualstudiocode&logoColor=white)](https://vscode.dev/redirect?url=vscode%3Achat-instructions%2Finstall%3Furl%3Dhttps%3A%2F%2Fraw.githubusercontent.com%2Fmcbodge%2Fclowder%2Fmain%2Finstructions%2Fcsharp.instructions.md)<br />[![Install in VS Code Insiders](https://img.shields.io/badge/VS_Code_Insiders-Install-24bfa5?style=flat-square&logo=visualstudiocode&logoColor=white)](https://vscode.dev/redirect?url=vscode-insiders%3Achat-instructions%2Finstall%3Furl%3Dhttps%3A%2F%2Fraw.githubusercontent.com%2Fmcbodge%2Fclowder%2Fmain%2Finstructions%2Fcsharp.instructions.md) | `**/*.cs` | C# and .NET design, errors, security, async, performance, and builds, including locked build output and stale build-server fixes. |
| [csharp-tests](instructions/csharp-tests.instructions.md)<br />[![Install in VS Code](https://img.shields.io/badge/VS_Code-Install-0098FF?style=flat-square&logo=visualstudiocode&logoColor=white)](https://vscode.dev/redirect?url=vscode%3Achat-instructions%2Finstall%3Furl%3Dhttps%3A%2F%2Fraw.githubusercontent.com%2Fmcbodge%2Fclowder%2Fmain%2Finstructions%2Fcsharp-tests.instructions.md)<br />[![Install in VS Code Insiders](https://img.shields.io/badge/VS_Code_Insiders-Install-24bfa5?style=flat-square&logo=visualstudiocode&logoColor=white)](https://vscode.dev/redirect?url=vscode-insiders%3Achat-instructions%2Finstall%3Furl%3Dhttps%3A%2F%2Fraw.githubusercontent.com%2Fmcbodge%2Fclowder%2Fmain%2Finstructions%2Fcsharp-tests.instructions.md) | `**/*Tests/**/*.cs`, `**/*.Test/**/*.cs`, `**/*Tests.cs`, `**/*Test.cs` | Test conventions and the xUnit v3 cancellation-token rule (xUnit1051) under warnings-as-errors. |
| [blazor](instructions/blazor.instructions.md)<br />[![Install in VS Code](https://img.shields.io/badge/VS_Code-Install-0098FF?style=flat-square&logo=visualstudiocode&logoColor=white)](https://vscode.dev/redirect?url=vscode%3Achat-instructions%2Finstall%3Furl%3Dhttps%3A%2F%2Fraw.githubusercontent.com%2Fmcbodge%2Fclowder%2Fmain%2Finstructions%2Fblazor.instructions.md)<br />[![Install in VS Code Insiders](https://img.shields.io/badge/VS_Code_Insiders-Install-24bfa5?style=flat-square&logo=visualstudiocode&logoColor=white)](https://vscode.dev/redirect?url=vscode-insiders%3Achat-instructions%2Finstall%3Furl%3Dhttps%3A%2F%2Fraw.githubusercontent.com%2Fmcbodge%2Fclowder%2Fmain%2Finstructions%2Fblazor.instructions.md) | `**/*.razor`, `**/*.razor.cs`, `**/*.razor.css` | Thin components, DbContext safety in Blazor Server circuits, authorization, workflow states, and MudBlazor markup. |
| [lean-code](instructions/lean-code.instructions.md)<br />[![Install in VS Code](https://img.shields.io/badge/VS_Code-Install-0098FF?style=flat-square&logo=visualstudiocode&logoColor=white)](https://vscode.dev/redirect?url=vscode%3Achat-instructions%2Finstall%3Furl%3Dhttps%3A%2F%2Fraw.githubusercontent.com%2Fmcbodge%2Fclowder%2Fmain%2Finstructions%2Flean-code.instructions.md)<br />[![Install in VS Code Insiders](https://img.shields.io/badge/VS_Code_Insiders-Install-24bfa5?style=flat-square&logo=visualstudiocode&logoColor=white)](https://vscode.dev/redirect?url=vscode-insiders%3Achat-instructions%2Finstall%3Furl%3Dhttps%3A%2F%2Fraw.githubusercontent.com%2Fmcbodge%2Fclowder%2Fmain%2Finstructions%2Flean-code.instructions.md) | Code files (`.cs`, `.razor`, `.ts`, `.js`, `.py`, `.ps1`, `.sh`, `.sql`, and variants) | The smallest correct, surgical change: reuse before writing, no speculative abstractions, root-cause fixes, every changed line traceable to the task. Adapted from [Ponytail](#about-ponytail) and the [Karpathy guidelines](#about-the-karpathy-guidelines). |

## 🎯 Skills

Skills load only when a request needs them. Install with the [GitHub CLI](https://cli.github.com/) 2.90 or later, or copy the folder to `~/.copilot/skills/`.

| Skill | Description | Install |
| --- | --- | --- |
| [cat-release-notes](skills/cat-release-notes/SKILL.md) | Drafts user-facing release notes from the commits between two git refs (default: latest tag to `HEAD`), grouped by work item and change type, and matches an existing `CHANGELOG.md` format. | `gh skills install mcbodge/clowder cat-release-notes` |
| [cat-install](skills/cat-install/SKILL.md) | Installs or updates the Clowder — agents, instructions, skills, hooks, and companion tools — into your user profile or a project's `.github/`, by running the `update-all` script. | `gh skills install mcbodge/clowder cat-install` |

## 🪝 Hooks

Hooks run a script at a point in an agent's lifecycle and enforce a rule regardless of what the model decides. They run in VS Code's **Local** agent harness, need the `chat.useHooks` setting (on by default) and a trusted workspace, and are in preview.

| Hook | Description | Events | Files |
| --- | --- | --- | --- |
| [git-guard](hooks/git-guard/) | Denies force pushes (`--force`, `--force-with-lease`, `-f`, `+refspec`), bulk staging (`git add -A`, `--all`, `-u`, `.`, `./`, `*`, `:/`), and `git commit -a` in terminal commands, and tells the agent to stage by explicit path. Asks you first before commands that discard work or delete branches: `reset --hard`, `clean -f`, `checkout` or `restore` of every file, `stash drop` or `clear`, `branch -D`, and remote branch deletion. Quoted text such as commit messages never triggers it. | `PreToolUse` | `git-guard.ps1`, `git-guard.sh`, `hooks.json` |
| [env-guard](hooks/env-guard/) | Denies running the app, applying migrations, or seeding against **Production** with an explicit error, and **asks** you first before the same against Test, Staging, or other pre-production environments. Catches `dotnet run`/`watch`, `dotnet <app>.dll`, `func start`, `dotnet ef database update`/`drop`, `Update-Database`/`Drop-Database`, and seed commands, but only when the command selects the environment (`ASPNETCORE_ENVIRONMENT`/`DOTNET_ENVIRONMENT`, `--environment`, or an `appsettings.<Env>.json` reference). Read-only commands (`dotnet ef migrations list`/`script`) and Development pass through untouched. | `PreToolUse` | `env-guard.ps1`, `env-guard.sh`, `hooks.json` |
| [planner-write-guard](hooks/planner-write-guard/) | Denies any file write whose target is not under `docs/plans/` or `/memories/`, so a read-only planning or audit agent can't edit the workspace no matter what earlier turns did. Read tools and writes to plan files pass through; writes to source, configuration, tests, or agent files are refused with a pointer to the **Execute plan** handoff. Gates `create_file`, `replace_string_in_file`, `multi_replace_string_in_file`, `insert_edit_into_file`, `create_directory`, `edit_notebook_file`, and `apply_patch`. | `PreToolUse` | `planner-write-guard.ps1`, `planner-write-guard.sh` |

**Install git-guard** by copying `git-guard.ps1` and `git-guard.sh` to `~/.copilot/hooks/`. The Plan Executor, PR Feedback Resolver, TDD Cycle, and Debugger declare it in their front matter. A front-matter hook runs only while its own agent is active, not inside the subagents it calls, which is why TDD Cycle declares it as well. To guard every agent, also copy `hooks.json` to `~/.copilot/hooks/git-guard.json`. On macOS and Linux, run `chmod +x ~/.copilot/hooks/git-guard.sh`.

**Install env-guard** the same way: copy `env-guard.ps1` and `env-guard.sh` to `~/.copilot/hooks/`, and `hooks.json` to `~/.copilot/hooks/env-guard.json` to guard every agent. The Plan Executor, PR Feedback Resolver, TDD Cycle, and Debugger declare it in their front matter alongside git-guard. On macOS and Linux, run `chmod +x ~/.copilot/hooks/env-guard.sh`. It reads the target environment from the command alone, so a command with no environment selector counts as Development and passes untouched; set `ASPNETCORE_ENVIRONMENT`/`DOTNET_ENVIRONMENT`, `--environment`, or reference an `appsettings.<Env>.json` to protect a run. Because it can't correlate a separate `export`/`$env:` line with a later run, keep the environment and the command together (for example `ASPNETCORE_ENVIRONMENT=Production dotnet run`).

**Install planner-write-guard** by copying `planner-write-guard.ps1` and `planner-write-guard.sh` to `~/.copilot/hooks/`. The four planners and the Auditor declare it in their front matter. On macOS and Linux, run `chmod +x ~/.copilot/hooks/planner-write-guard.sh`. Unlike git-guard and env-guard, **do not** install it globally with a `hooks.json`: a global write-guard would also block the Plan Executor and every other editing agent. It ships front-matter-only on purpose, so it binds just to the read-only planning and audit agents, and emits both the top-level and nested decision so VS Code, the Copilot CLI, and the cloud agent all honor it.

## Token economics

The team is built so a context window holds only what the current turn needs. What actually loads:

| Piece | Loads when | Always-on cost |
| --- | --- | --- |
| Agent prompt | You pick the agent, or one of the three model-invocable agents is handed off | None — only one loads per conversation |
| Instruction file | An agent edits a file matching its `applyTo` | None in chats that don't touch those files |
| Skill | A request matches the skill | Description only, and only for installed skills |
| Hook | Never — it runs as a script at a lifecycle point | None |
| Session memory | An agent re-reads its own notes after a compaction | A one-line summary, not raw files |

Because only one agent loads per conversation, the repeated dev-environment and graph-first passages across agents **never co-occur** — deduplicating them across files would save nothing at runtime. The real levers are per-prompt density (section references, banned filler, tables over prose) and short always-on description strings.

### Agent registry & token weight

Weight is the relative size of the prompt that loads when the agent runs (●○○ light · ●●○ medium · ●●● heavy). None of it rides along while the agent is idle.

| Agent | Role | Weight |
| --- | --- | --- |
| Planner · Planner (DevOps) | Research + interview → deterministic plan | ●●● |
| Plan Executor | Run the plan test-first, commit, review, update work items | ●●● |
| Auditor | Rank findings worst-first → plan | ●●● |
| Debugger | Reproduce → root-cause → hand off | ●●○ |
| PR Feedback Resolver | Review comments → commits + replies | ●●○ |
| TDD Cycle | One task, Red → Green → Refactor | ●●○ |
| Code Reviewer | Read-only review by severity | ●○○ |
| C# · MudBlazor Engineer | Hands-on implementation | ●○○ |
| Code Simplifier | Behavior-preserving cleanup | ●○○ |
| TDD Red · Green · Refactor | One phase each | ●○○ |

## Install or update everything

One script installs or updates everything — this repo's agents, instructions, skills, and hooks — then updates the external companions in [Prerequisites and companions](#prerequisites-and-companions) (playwright-cli, the azure-devops-cli skill, and graphify) when their CLIs are present. Run it from anywhere: it reuses the clone it runs from, or clones to `~/.copilot/.cache/clowder` on first run (override with `-RepoDir` / `$env:CLOWDER_DIR`, or `CLOWDER_DIR`). It clones or pulls first, so the same command is both a first-time install and an update. Each tool it can't find is skipped with a note. To install into a repository's `.github/` instead of your user profile, pass `-ProjectDir <repo>` (PowerShell) or `--project <repo>` (bash); each run targets one location only — your user profile or that project's `.github/`, never both. From the chat, the [cat-install](skills/cat-install/SKILL.md) skill runs it for you.

**Windows (PowerShell)** — from a clone, or bootstrap from anywhere without one:

```powershell
powershell -ExecutionPolicy Bypass -File clowder\scripts\update-all.ps1
# no clone yet (trusts and runs the remote script):
irm https://raw.githubusercontent.com/mcbodge/clowder/main/scripts/update-all.ps1 | iex
```

**macOS and Linux** — from a clone, or bootstrap from anywhere without one:

```bash
bash clowder/scripts/update-all.sh
# no clone yet (trusts and runs the remote script):
curl -fsSL https://raw.githubusercontent.com/mcbodge/clowder/main/scripts/update-all.sh | bash
```

The script copies instructions to all three places that read them: VS Code's and Insiders' profile `prompts` folders, and `~/.copilot/instructions/` for the Copilot CLI and Agent Host. Project mode writes to a repository's `.github/` — read by GitHub Copilot in **Visual Studio** and many other agents — but installs only agents, instructions, and skills, since hooks are a VS Code feature with no `.github` home.

<details>
<summary>Prefer to copy by hand? Manual user-profile and project installs</summary>

Clone the repository and copy each folder to its user-level location. Run the same commands again after `git pull` to update; one-click installs are copies too. Copying never deletes: if you installed earlier versions under other file names, remove them, or the agent picker lists both.

**Windows (PowerShell)**

```powershell
git clone https://github.com/mcbodge/clowder.git
Set-Location clowder
$copilot = Join-Path $HOME '.copilot'
New-Item -ItemType Directory -Force "$copilot\agents", "$copilot\skills", "$copilot\hooks", "$copilot\instructions", "$env:APPDATA\Code\User\prompts", "$env:APPDATA\Code - Insiders\User\prompts" | Out-Null
Copy-Item agents\*.agent.md "$copilot\agents"
Copy-Item skills\* "$copilot\skills" -Recurse -Force
Copy-Item hooks\git-guard\git-guard.ps1, hooks\git-guard\git-guard.sh, hooks\env-guard\env-guard.ps1, hooks\env-guard\env-guard.sh, hooks\planner-write-guard\planner-write-guard.ps1, hooks\planner-write-guard\planner-write-guard.sh "$copilot\hooks"
foreach ($d in "$copilot\instructions", "$env:APPDATA\Code\User\prompts", "$env:APPDATA\Code - Insiders\User\prompts") { Copy-Item instructions\*.instructions.md $d }
```

**macOS and Linux**

```bash
git clone https://github.com/mcbodge/clowder.git
cd clowder
mkdir -p ~/.copilot/agents ~/.copilot/skills ~/.copilot/hooks ~/.copilot/instructions
cp agents/*.agent.md ~/.copilot/agents/
cp -R skills/* ~/.copilot/skills/
cp hooks/git-guard/git-guard.* hooks/env-guard/env-guard.* hooks/planner-write-guard/planner-write-guard.* ~/.copilot/hooks/ && chmod +x ~/.copilot/hooks/git-guard.sh ~/.copilot/hooks/env-guard.sh ~/.copilot/hooks/planner-write-guard.sh
cp instructions/*.instructions.md ~/.copilot/instructions/
BASE="$HOME/Library/Application Support"   # Linux: $HOME/.config
for ed in "Code" "Code - Insiders"; do mkdir -p "$BASE/$ed/User/prompts" && cp instructions/*.instructions.md "$BASE/$ed/User/prompts/"; done
```

For a project's `.github/` instead of your user profile, copy agents, instructions, and skills into the target repository (hooks have no `.github` home):

**Windows (PowerShell)** — set `$proj` to the repository root:

```powershell
$proj = 'C:\path\to\your\repo'
New-Item -ItemType Directory -Force "$proj\.github\agents", "$proj\.github\instructions", "$proj\.github\skills" | Out-Null
Copy-Item agents\*.agent.md "$proj\.github\agents"
Copy-Item instructions\*.instructions.md "$proj\.github\instructions"
Copy-Item skills\* "$proj\.github\skills" -Recurse -Force
```

**macOS and Linux** — set `PROJ` to the repository root:

```bash
PROJ=~/path/to/your/repo
mkdir -p "$PROJ"/.github/{agents,instructions,skills}
cp agents/*.agent.md "$PROJ"/.github/agents/
cp instructions/*.instructions.md "$PROJ"/.github/instructions/
cp -R skills/* "$PROJ"/.github/skills/
```

</details>

## Prerequisites and companions

The agents call these tools; they aren't included here. Install them from their sources so they stay current.

| Companion | Used by | Get it |
| --- | --- | --- |
| [azure-devops-cli](https://github.com/github/awesome-copilot/tree/main/skills/azure-devops-cli) skill | CAT Planner (DevOps), Plan Executor (work-item plans and pull requests), PR Feedback Resolver, Debugger, cat-release-notes | `gh skills install github/awesome-copilot azure-devops-cli`, plus the [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) with `az extension add --name azure-devops` and `az login` |
| [playwright-cli](https://github.com/microsoft/playwright-cli) | Plan Executor, Debugger, PR Feedback Resolver, MudBlazor Engineer, C# Engineer, and TDD Cycle, TDD Red, and TDD Green for UI bugs | `npm install -g @playwright/cli@latest`, then `playwright-cli install --skills`. The Plan Executor, Debugger, and PR Feedback Resolver keep its `.playwright-cli/` snapshots and their own `logs/` out of `git status` through `.git/info/exclude`, never `.gitignore` |
| [MudBlazor MCP server](https://github.com/mcbodge/MudMCP) | MudBlazor Engineer, TDD Cycle, the `(MudBlazor)` planner and executor variants, `blazor` instructions | Follow its Quick Start and name the server `mudblazor` in `.vscode/mcp.json`; the agents only look for `mudblazor/*` tools |
| [graphify](https://github.com/Graphify-Labs/graphify) (optional) | The planners, the Plan Executor variants, Debugger | `uv tool install graphifyy` (or `pipx install graphifyy`). The planners build the graph on first run with `graphify extract . --code-only` (kept out of `git status` via `.git/info/exclude`); you can also build it once per repository yourself. The agents refresh it with `graphify update .` and fall back to search when the graph is unavailable |
| Aspire dashboard MCP server (optional) | Debugger | Register the dashboard's MCP endpoint as `aspire-dashboard` in `.vscode/mcp.json` |
| [Trojan Skill Hunter](https://github.com/github/awesome-copilot/blob/main/agents/trojan-skill-hunter.agent.md) (optional) | You, before trusting any third-party agent, skill, or hook | Install it from awesome-copilot and run it once per new plugin |

## Visual Studio 2026

Visual Studio reads the same file formats with fewer features, and has no install buttons: copy the files.

| Piece | Where it goes | Notes |
| --- | --- | --- |
| Agents (18.4 or later) | `%USERPROFILE%\.github\agents\` for every solution (change it in **Tools > Options > GitHub > Copilot**), or `.github/agents/` in a repository | Visual Studio documents only `name`, `description`, `model`, and `tools`, and its tool names differ (`code_search`, `readfile`, `editfiles`, `runcommandinterminal`, ...). Delete each agent's `tools` line to enable every tool, or replace it with names from the chat **Tools** panel. Handoff buttons, subagents, and hooks are VS Code features, so run the Plan Executor and PR Feedback Resolver from VS Code. |
| Instructions | `.github/instructions/` in the repository | `applyTo` works once **Enable custom instructions to be loaded from .github/copilot-instructions.md files and added to requests** is on (**Tools > Options > GitHub > Copilot > Copilot Chat**). The only user-level file is `%USERPROFILE%\copilot-instructions.md`, which has no `applyTo` and applies to every request. |
| Skills (18.5 or later) | `%USERPROFILE%\.copilot\skills\` or `.github/skills/` | Work as-is. |
| Hooks | - | Not supported; the agents' written commit rules still apply. |
| MCP servers | `%USERPROFILE%\.mcp.json`, or the solution's `.mcp.json` or `.vscode\mcp.json` | A repository's `.vscode/mcp.json` works in both editors, so one `mudblazor` entry there serves both. |

## Other agents & IDEs

Beyond GitHub Copilot (VS Code, Visual Studio, the CLI), these files work with other agents to varying degrees. The honest picture: **skills** (`SKILL.md`) and the repo-wide **instructions** port widely; the **agents** (`.agent.md`) are a Copilot / Visual Studio format that other tools don't read natively; and most non-Copilot tools take a single always-on rules file (`AGENTS.md`) or their own rules folder rather than this repo's per-file `applyTo` instructions, so instruction content copies but its front matter needs a small tweak to each tool's format.

| Agent / IDE | Where it reads customizations | What drops in |
| --- | --- | --- |
| GitHub Copilot (VS Code, Visual Studio, CLI) | `.github/agents`, `.github/instructions`, `.github/skills`, `~/.copilot/`, the VS Code profile `prompts` folder | Everything, as-is |
| Any agent that reads `AGENTS.md` (Antigravity, Zed, Amp, Jules, Codex, Aider, Junie, Goose) | `AGENTS.md` at the repo root (Antigravity also `.agents/rules/`) | Instruction content as one always-on file; skills via the tool's skills folder |
| Cursor | `.cursor/rules/*.mdc` (and `AGENTS.md`) | Instruction content as `.mdc` rules (convert `applyTo` to `globs`) |
| Windsurf | `.windsurf/rules/*.md` | Instruction content as rules |
| Cline | `.clinerules/*.md` or `~/.cline/rules/` (and `AGENTS.md`); skills in `.agents/skills/` | Instruction content as rules; skills as-is |
| Kiro | `.kiro/steering/*.md` | Instruction content as steering rules |

Rule of thumb: commit the pieces to `.github/` for Copilot and Visual Studio ([above](#install-or-update-everything)); add an `AGENTS.md` (or the matching rules file) for any other agent; and drop the skill folders into whatever skills directory the tool scans. Paths follow Ponytail's verified [agent-portability table](https://github.com/DietrichGebert/ponytail/blob/main/docs/agent-portability.md).

## About Ponytail

[Ponytail](https://github.com/DietrichGebert/ponytail) makes coding agents write the smallest correct change. Its always-on mode relies on host hooks and `/ponytail` level commands, and its own [portability table](https://github.com/DietrichGebert/ponytail/blob/main/docs/agent-portability.md) lists GitHub Copilot as instruction-only. In VS Code, Copilot loads just its six skills, and a skill applies only when the model decides to use it, so the mode never stays on.

[lean-code](instructions/lean-code.instructions.md) adapts Ponytail's rules for this team: they attach automatically whenever an agent edits a code file, in VS Code and in Visual Studio, and cost nothing in other chats. The Code Reviewer covers over-engineering in its reviews. If you don't use Ponytail in Copilot CLI, where its plugin hooks do work, uninstall it with `copilot plugin uninstall ponytail@ponytail` so its skill descriptions stop riding along on every request.

## About the Karpathy guidelines

[andrej-karpathy-skills](https://github.com/multica-ai/andrej-karpathy-skills) turns [Andrej Karpathy's observations](https://x.com/karpathy/status/2015883857489522876) on LLM coding pitfalls into four principles: think before coding, simplicity first, surgical changes, and goal-driven execution. It ships them as one skill, `karpathy-guidelines`, which this team doesn't install: a skill applies only when the model decides to load it, its description rides along on every request, and most of it is already covered here, with simplicity in lean-code, questions before code in the planners' interviews, and verifiable goals in TDD and each task's Done-when criterion.

The parts that were missing now live in [lean-code](instructions/lean-code.instructions.md), so they attach whenever an agent edits code: state assumptions and ask rather than guess, define the check that proves success before changing code, keep edits surgical so every changed line traces to the task, and skip handling for cases that can't happen. The Code Reviewer flags drive-by edits as scope creep.

## License

[MIT](LICENSE) © 2026 Manuel Grillo. Some files adapt MIT-licensed work from [github/awesome-copilot](https://github.com/github/awesome-copilot), [Ponytail](https://github.com/DietrichGebert/ponytail), and the [Karpathy guidelines](https://github.com/multica-ai/andrej-karpathy-skills). The plan infrastructure shared by the planners and the Plan Executor (plan files, naming, status values, ID prefixes, and template) is inspired by awesome-copilot's [implementation-plan.agent.md](https://github.com/github/awesome-copilot/blob/main/agents/implementation-plan.agent.md). The planners' interview — one decision at a time, each with a recommended answer, and the codebase explored before you're asked — is inspired by [mfse-plan-on-roids](https://github.com/MFSoftwareEngineering/mfse-softwarefactory/blob/main/agents/mfse-plan-on-roids.agent.md). See [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md). Companion tools are not included and keep their own licenses.
