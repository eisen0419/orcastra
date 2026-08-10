---
name: orca-orchestrate
description: Coordinate Orca orchestration workers from Claude Code — dispatch a task, confirm it actually arrived, collect completion, and verify before closing. Use when acting as an Orca coordinator, when a dispatch or receipt looks wrong, when a worker seems stuck or vanished, or when an orchestration command behaves in a way the official guide does not explain.
---

# Running a reliable Orca coordinator loop

The official guide is the source of truth for the API. Read it on demand:

```bash
orca skills get orchestration     # full orchestration guide for your build
orca agent-context                # machine-readable command schema
```

This skill covers only what that guide leaves out: how to tell a real signal
from a fake one, and what to do when the runtime surprises you.

## Four rules that outlive any version

Orca moves fast. Specific traps come and go; these four do not. The *rules* are
durable — the field names below that illustrate them are not. Take those as
pointers, not claims, and check the stamp in the reference before you depend on
one.

1. **A receipt is not ground truth.** A timeout does not mean the write failed.
   An error does not mean nothing happened. An empty list does not mean the
   thing is absent. Always re-read the state with a read-only command before
   you retry — especially before anything irreversible.
2. **Delivery is confirmed, never inferred.** "The terminal looks busy" is not
   delivery. A `worker-start` receipt reporting `stage: input_accepted` is —
   it is a runtime-level acknowledgement. If you did not see it, assume the
   prompt never landed.
3. **Collect completion through a binding-independent channel.** Do not wait on
   the `worker_done` push: it is routed by the run binding, and a stolen binding
   or a rotted handle drops it silently. Poll a disk sentinel the worker writes,
   with `task-list --run <run_id>` as the backup — and bound every wait.
4. **A worker's self-report is not verification.** Re-run the acceptance check
   yourself and read what the worker actually produced. "It said done" is a
   claim, not evidence.

## Where to go next

Load these on demand — none of them is loaded with this entry point.

| You want to… | Read |
|---|---|
| run your first supervised worker end to end | `docs/quickstart.md` in the orcastra repo |
| understand how Orca records state, so you can read anomalies correctly | `references/mechanics.md` |
| look up a symptom you are seeing right now | `references/pitfalls.md` |
| write a brief that can be accepted mechanically | `references/delivery-contract.md` |
| decide how hard to review, and when the loop is closed | `references/review-loop.md` |
| name your worker roles instead of improvising each time | `references/roster.md` |
| check your environment before blaming the code | `tools/orca-doctor` in the orcastra repo |
| see which Orca builds these claims were checked against | `docs/compat.md` in the orcastra repo |

Routing: *"how do I do it"* → quickstart. *"why did it do that"* →
pitfalls. *"what is going on in there"* → mechanics. *"how do I hand work off
and judge what returns"* → delivery-contract, then review-loop.

## Reading the version stamps

Every behavioral claim here carries a stamp, because Orca drifts faster than
prose can track: `verified` was re-checked on that build; `observed` is carried
from an earlier observation — most pitfalls are, since reproducing them means
running the destructive command that causes them; `historical` means the
trigger is gone, kept as a lesson. Full definitions live in `CONTRIBUTING.md`.

An unstamped claim about Orca behavior is not trustworthy — including one you
write yourself. If your build is newer than a stamp and the behavior differs,
the stamp is what is wrong; re-verify it.

## When this skill does not apply

- Installing or configuring Orca itself, or driving its GUI.
- Multi-agent frameworks other than Orca.
- Anything the official guide already answers — point at it instead of
  restating it, so it cannot drift.
