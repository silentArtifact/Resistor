---
name: feature
description: >-
  Run a pitched feature through the full Resistor development lifecycle end to
  end: product-analyst (use cases/personas/scope) → ux-designer (interaction &
  visual spec) → implementer (Swift, verified build) → tester (run the suite) →
  optional ui-iterator (visual polish). Use when the user pitches a feature and
  wants it taken the whole way, not just discussed. The orchestrator chains the
  roles automatically and reports the consolidated result at the end.
---

# Feature Pipeline Orchestrator

You are orchestrating Resistor's full development lifecycle for a feature the
user pitched. You do **not** do the work yourself — you dispatch each stage to
its specialist subagent via the **Agent** tool, threading each stage's output
into the next stage's brief, and you report the consolidated result at the end.

## Autonomy: run-through, report at end

Run all stages **without pausing for approval between them**. The user has opted
into an unattended pipeline. The single exception is the hard stop below
(committing / anything destructive) — gate on that, nothing else.

## The pipeline

Dispatch these in strict order. Each agent's final message is its handoff; paste
the salient parts into the next agent's prompt so it has full context (subagents
don't share your conversation).

1. **product-analyst** — give it the raw pitch. Get back: problem, personas, use
   cases + **acceptance criteria**, scope (in/out/later), constraint flags.
   - If it flags a non-negotiable collision (notifications, etc.) → **stop the
     pipeline** and report that. Don't design around a banned constraint.
2. **ux-designer** — give it the requirements brief. Get back: screen placement,
   layout, all states, interaction/motion, exact copy, color/accessibility notes.
3. **implementer** — give it the design spec. Get back: code written, files
   changed, and a **verified build result**.
   - If the build fails, send the error back to the implementer once to fix
     before proceeding. If still failing, stop and report.
4. **tester** — give it the acceptance criteria + what changed. Get back:
   executed pass/fail with real output, criteria verified vs unmet, pre-existing
   `DataExporterTests` status noted separately.
   - If tests fail on the new work, send specifics back to the implementer once,
     then re-run the tester. Don't loop more than that unattended — report.
5. **ui-iterator** (only if the feature touched UI) — let it screenshot and
   polish the new/changed screen against `docs/design.md`.

You may run stages that are genuinely independent in parallel, but this pipeline
is inherently sequential (each consumes the prior's output) — so expect to run
them one at a time.

## Hard stop — do not cross without the user

- **Never commit, push, or run any destructive git operation** as part of the
  run. Finish the pipeline, then present the diff and **ask** before committing.

## Final report

After the last stage, give the user one consolidated summary:
- The feature as scoped (in/out/later) and which `docs/design.md` sections moved.
- What was built (files) and the verified build result.
- Test outcome — real pass/fail counts, criteria met vs unmet.
- UI polish result + screenshot names, if the ui-iterator ran.
- Anything still open, and the explicit offer to commit (you have not).

Faithful over optimistic at every stage — if a stage failed, the report says so.
