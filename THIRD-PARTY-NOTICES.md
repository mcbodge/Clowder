# Third-party notices

Some files in this repository adapt material from the projects below. The adapted files were rewritten and changed for this project; the original copyright notices and license text are reproduced here as those licenses require. Companion tools the README points to are not included and keep their own licenses.

## github/awesome-copilot

- Source: <https://github.com/github/awesome-copilot>
- Copyright GitHub, Inc.
- License: MIT (text below)
- Adapted in:
  - `agents/cat-tdd-red.agent.md`, `agents/cat-tdd-green.agent.md`, `agents/cat-tdd-refactor.agent.md`, and `agents/cat-tdd-cycle.agent.md`, from the TDD Red, Green, and Refactor Phase agents.
  - `agents/cat-csharp-engineer.agent.md`, `instructions/csharp.instructions.md`, and `instructions/csharp-tests.instructions.md`, from the C# Expert agent.
  - `agents/cat-csharp-mcp-engineer.agent.md`, from the C# MCP Server Expert agent in the `csharp-mcp-development` plugin.
  - The plan infrastructure of `agents/cat-planner.agent.md`, `agents/cat-planner-devops.agent.md`, and `agents/cat-plan-executor.agent.md` (plan files with front matter and status values, `{purpose}-{component}-{version}` file names, `REQ-`/`TASK-`-style ID prefixes, phase task tables with Completed and Date columns, and the section template), inspired by and adapted from [`agents/implementation-plan.agent.md`](https://github.com/github/awesome-copilot/blob/main/agents/implementation-plan.agent.md) (Implementation Plan Generation Mode).

## Ponytail

- Source: <https://github.com/DietrichGebert/ponytail>
- Copyright (c) 2026 DietrichGebert
- License: MIT (text below)
- Adapted in: `instructions/lean-code.instructions.md`.

## Karpathy guidelines (andrej-karpathy-skills)

- Source: <https://github.com/multica-ai/andrej-karpathy-skills> (formerly `forrestchang/andrej-karpathy-skills`), derived from [Andrej Karpathy's observations](https://x.com/karpathy/status/2015883857489522876) on LLM coding pitfalls
- Author: forrestchang (named in the project's `.claude-plugin/plugin.json`; the repository has no LICENSE file or copyright line)
- License: MIT, as declared in the project's README, `skills/karpathy-guidelines/SKILL.md`, and `.claude-plugin/plugin.json` (text below)
- Adapted in: `instructions/lean-code.instructions.md` (assumptions and questions before code, a success check before changing code, surgical edits, no handling for impossible cases) and the scope-creep check in `agents/cat-code-reviewer.agent.md`.

## Inspiration only

No text or code reused, listed for credit:

- `agents/cat-code-simplifier.agent.md` follows the idea of the code-simplifier agent in [anthropics/claude-plugins-official](https://github.com/anthropics/claude-plugins-official).
- The interview protocol in `agents/cat-planner.agent.md` and `agents/cat-planner-devops.agent.md` (one decision per question via the ask-questions tool, each with a recommended answer, and the codebase explored before the user is asked) follows the idea of Michele Ferracin's[`agents/mfse-plan-on-roids.agent.md`](https://github.com/MFSoftwareEngineering/mfse-softwarefactory/blob/main/agents/mfse-plan-on-roids.agent.md) in MFSoftwareEngineering/mfse-softwarefactory.

## MIT License text

Applies to the material adapted from each MIT-licensed project above, together with that project's copyright notice.

```text
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
