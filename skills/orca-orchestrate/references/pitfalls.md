# Orchestration Pitfalls

A symptom-driven map of the traps that cost real time when running a Claude Code
coordinator over Orca orchestration. Come here with a "why did it do that?"
question; leave with a judgment you can run and a fix you can apply.

This file is the **negative space** of the official guide. Run
`orca skills get orchestration` first — anything that guide already explains is
not restated here, only pointed at. For the positive mechanism model (how agent
detection, terminal model/view, run binding, and hibernation actually work), see
`./mechanics.md`. This file covers only **symptom → judgment → fix**, and every
entry carries a version stamp.

## How to use this map

1. Match your symptom, not your hypothesis. Scan the **Symptom** lines first.
2. Run the **How to tell** check before acting — it is the most valuable field
   in each entry and exists to distinguish the trap from look-alikes.
3. Respect the stamps. Orca drifts fast; a conclusion without a stamp is inert.

## Stamp tiers

- `(verified: Orca <ver>, <date>)` — the claim was re-checked with read-only
  commands (`--help`, `orca skills get`, `defaults read`) on the dated build.
- `(observed: Orca <ver>, <date>)` — carried from an earlier field observation;
  the behavior was not reproduced for this entry (most pitfalls are like this,
  because reproducing them is disruptive on a live orchestration).
- `(historical: <ver/date>; <why it may no longer apply>)` — the trigger has
  disappeared; kept only as a warning and a lesson.

Where an entry has a *parameter face* (a flag or command still present, checked
via `--help` this round) that is **verified**, but a *behavior* that is only
**observed**, the two layers are written separately inside the entry and the
formal stamp reflects the behavior layer. Do not promote a behavior to
`verified` just because the flag still exists.

---

## Reading the receipts — three habits (read before any entry)

Orca orchestration is an RPC layer, and every RPC returns a receipt. The single
most durable lesson in this file is that **a receipt is not ground truth**.
Specific traps come and go with versions; this habit does not. Three forms:

### Timeout ≠ did-not-take-effect

A `Request timed out` receipt does **not** mean the action failed. The runtime
may have completed the write and only the reply was lost or delayed.

**Verify, don't assume:** re-read the actual state with a read-only command
before retrying. If you dispatched a task, run `orca orchestration task-list
--run <run_id> --json` and look for the row. If you created a task, look for it
by spec, not by whether the create call returned cleanly. Never retry a mutating
command on the strength of a timeout alone — for irreversible actions (see the
task-irreversibility entry) a blind retry creates duplicates you cannot delete.

*Ground: relay-era `orca.cli` RPC timeout observations, Orca 1.4.13x–1.4.138
(2026-07/08). The habit is version-independent; the specific 300 s blocking
incidents that produced it are historical — that transport is retired — but the
underlying "reply ≠ effect" property of any RPC layer is not.*

### Error ≠ took-effect (and success ≠ took-effect either)

An error receipt does not prove the action happened, and a success receipt does
not prove it happened either. Both directions bite:

- A `close` that returns `tab_not_found` may have left the target untouched —
  or another force may have removed it. You cannot tell from the receipt.
- A `dispatch` that returns `Dispatched → …` may have delivered nothing to the
  worker (see the `--inject` entry).

**Verify, don't assume:** check the artifact the action was supposed to change.
For a terminal close, confirm with `orca terminal list --json` and, if needed,
the process list — not with the close call's exit code. For a dispatch, confirm
the worker actually received the prompt (see delivery checks under the
`--inject` and cold-start entries). Treat the receipt as a hint, never as proof.

*Ground: field observations across Orca 1.4.13x–1.4.164 (2026-07/08).*

### Empty list ≠ does-not-exist

A command that returns an empty list (exit 0, no error) does not prove the thing
you are looking for is absent. The list may be stale, filtered, or momentarily
inconsistent.

**Verify, don't assume:** especially before an irreversible action. If you are
checking whether a task already exists before creating one, do **not** filter by
status (`task-list --status completed` hides completed rows you still need to
see for dedup). List the full set for the run — `task-list --run <run_id> --json`
— and grep by spec. A momentary empty result is a signal to wait and re-query,
never a signal to proceed as if nothing exists.

*Ground: a `task-list` returning an empty list that self-healed minutes later,
observed Orca ~1.4.13x (2026-07).*

---

## Entries

### 1. After an Orca update, orchestration commands on the adopted run are rejected as read-only

**Symptom.** Right after an Orca update, `orchestration` commands that omit
`--run` return a single line like `This retained legacy coordinator could not
prove its original process identity. No effects were applied.` with exit 0 and
no task rows printed. It looks like the runtime is wedged or your connection is
broken.

**Mechanism.** On update, Orca adopts the live pre-update orchestration state
into an ordinary Run whose objective is `Recovered orchestration work from a
contract update`. That adopted Run has no coordinator handle — it is ownerless.
Orca fails closed: any process that cannot prove it is the original coordinator
is degraded to read-only inspection and may not mutate. This is by design, not a
hang. The official guide covers this under *Contract Migration*. The recovery
command `run-use --id <adopted_run_id> --takeover-legacy` and the adopted-run
objective string are documented in the guide (read on Orca 1.4.176); the
rejection behavior itself was not reproduced for this entry.

**How to tell.** Run `orca orchestration run-list --json`. If you can list runs
and they return normally, the runtime is healthy — you are not wedged. Look for
a Run whose objective is `Recovered orchestration work from a contract update`.
Read commands that name that Run explicitly — `task-list --run <run_id>`,
`run-show --id <run_id>` — still work; write commands are rejected even with
`--run`, because the runtime degrades ownerless adopted Runs to read-only
(fail-closed). If `run-list`
itself is unresponsive, that is a different problem (runtime health, not
contract migration).

**What to do.** Always pass `--run <run_id>` explicitly to `orchestration`
subcommands; do not rely on implicit binding right after an update. For a frozen
ownerless adopted Run, the documented recovery is `run-use --id <adopted_run_id>
--takeover-legacy` run from a live coordinator terminal — success depends on
that terminal proving liveness and ownership (the guide states this explicitly).
If the invoking terminal cannot prove authority, the Run stays read-only; the
practical path is to abandon the frozen queue and rebuild tasks in a fresh Run
(`run-create`), since the old tasks cannot be mutated or deleted (see entry 5).

**Stamp.** `(observed: Orca 1.4.138-rc.7, 2026-07-31)`

---

### 2. `dispatch` without `--inject` returns success but delivers no prompt

**Symptom.** You run `orca orchestration dispatch --task <task_id> --to
<handle>` (no `--inject`) and get a success receipt like `Dispatched →
ctx_… [dispatched]`. The worker terminal shows nothing new and never starts the
task.

**Mechanism.** Without `--inject`, `dispatch` only records the task↔terminal
binding for tracking. It injects no text into the terminal. The success receipt
reflects the binding being created, not a prompt being delivered. The official
guide states this division of labor: `--inject` is what sends the spec plus
preamble into a recognized agent CLI; for a bare shell you omit `--inject`,
dispatch only if you want tracking, then send the prompt yourself. The `--inject` flag is present on
`dispatch --help` as of Orca 1.4.176 (verified); the no-delivery behavior was
not reproduced for this entry.

**How to tell.** Read the worker terminal: `orca terminal read --terminal
<handle> --json`. If the input area is empty (or still shows the agent's default
placeholder) and the agent has produced no new session/transcript activity since
launch, nothing was delivered — regardless of the dispatch receipt. Contrast
with a genuine delivery failure (entry 3), where `--inject` was used but the
prompt vanished during cold start.

**What to do.** If you wanted the prompt injected, re-dispatch with `--inject`
on a ready task (see entry 6 if the task is already `dispatched`). If you
intentionally dispatched without `--inject` (e.g. a bare-shell worker), follow up
with `orca terminal send --terminal <handle> --text "<prompt>" --enter --json`
to actually deliver the prompt. Treat the dispatch receipt as proof of binding
only, never as proof of delivery.

**Stamp.** `(observed: Orca 1.4.13x, 2026-07-27)`

---

### 3. Injecting before the agent TUI is ready silently swallows the prompt

**Symptom.** You create a terminal and immediately `dispatch --inject` (or
`terminal send`) into it. The call returns success, but the worker never acts on
the task. The agent's input box still shows its default placeholder (e.g.
`Explain this codebase`), and the agent has created no new session/transcript
record since launch.

**Mechanism.** While the agent CLI is still cold-starting — typically loading its
MCP servers — injected input can disappear with zero error. The dispatch/send
receipt reports success because the bytes were accepted by the terminal layer;
the agent TUI had not finished booting and did not register them. The official
guide prevents this by prescribing `orca terminal wait --terminal <handle> --for
tui-idle --timeout-ms <n>` before dispatch; the failure mode is what happens when
that wait is skipped or raced.

**How to tell.** Two signals together: (a) the agent's input box still shows the
default placeholder, and (b) the agent has produced no new session/transcript
activity since launch. Either alone is weaker — a busy agent may have cleared the
placeholder for other reasons — but both together, immediately after an inject,
mean the prompt never landed. A follow-up `terminal send --text "" --enter` (or
re-sending the prompt) lands normally, confirming the channel is fine and the
loss was a startup race.

**What to do.** Wait for `tui-idle` before every inject on a freshly created
terminal, exactly as the guide shows. If you already hit the swallow, re-send
the prompt with `terminal send --text "<prompt>" --enter`; do not assume the
task is underway. For agents whose CLI creates a session/transcript file only on
first real input, the absence of that file is a clean negative signal — no file
means no input was ever registered.

**Stamp.** `(observed: Orca 1.4.138-rc.7, 2026-08-01)`

---

### 4. `terminal send` without `--enter` leaves the text in the input box, unsubmitted

**Symptom.** You run `orca terminal send --terminal <handle> --text "<prompt>"`
and get `Sent N bytes to term_…`. In the TUI the text sits on the input line
after the prompt, unsubmitted — the agent never starts working.

**Mechanism.** Without `--enter`, `terminal send` places text into the input box
but does not submit it. The receipt counts bytes accepted, not a submission. The
`--enter` flag is present on `terminal send --help` as of Orca 1.4.176
(verified); the no-submit behavior was not reproduced for this entry.

**How to tell.** `orca terminal read --terminal <handle> --json` shows the text
sitting on the input line and the agent at 0 % context / idle. Contrast with
entry 2 (dispatch bound but nothing delivered — there the input box is empty)
and entry 3 (inject during cold start — placeholder still shown, no session
activity).

**What to do.** Send a follow-up `terminal send --terminal <handle> --text ""
--enter --json` to submit what is already in the box. Going forward, always pass
`--enter` when you mean to submit (`--text "<prompt>" --enter`). Reserve
no-`--enter` sends for deliberately pre-filling the input for a human.

**Stamp.** `(observed: Orca 1.4.13x, 2026-08-02)`

---

### 5. There is no delete or cancel verb for tasks

**Symptom.** You created a duplicate or wrong task and reach for
`orca orchestration task-delete` / `task-cancel`. The command does not exist.

**Mechanism.** The `orchestration` command surface (verified via
`orca orchestration --help` on Orca 1.4.176) has `task-create`, `task-list`,
`task-update`, plus dispatch/worker/gate verbs — no delete, no cancel. The only
mutation is `task-update --status`, whose valid values are `pending, ready,
dispatched, completed, failed, blocked` (no `deleted`). Tasks are an execution
queue, not an archive: once created, a task row is permanent.

**How to tell.** `orca orchestration --help` lists no delete/cancel subcommand;
`orca orchestration task-update --help` lists no `deleted` status. Both checked
on Orca 1.4.176.

**What to do.** You cannot remove a wrong task. The least-misleading fix is
`task-update --id <task_id> --status completed --result '{"note":"DUPLICATE,
superseded by <task_id>"}'` — completed + a result note pointing at the real
task. Do **not** mark it `failed` or `blocked`: those statuses read as a real
problem and add noise to coordinator sweeps. Because deletion is impossible,
dedup **before** creating: list the full task set for the run and match on spec
(see entry 6).

**Stamp.** `(verified: Orca 1.4.176, 2026-08-09)`

---

### 6. A dispatched task cannot be re-dispatched; dedup must scan the full list

**Symptom.** A worker window died or was misconfigured, so you re-run
`orca orchestration dispatch --task <task_id> --to <new_handle>`. It returns
`Task <task_id> is dispatched; only ready tasks can be dispatched.` Separately:
you checked `task-list --status ready` before creating a task, saw nothing, and
created a duplicate of a task that was actually already there under a different
status.

**Mechanism.** Only tasks in `ready` can be dispatched. Once dispatched, the task
holds `dispatched` until a `worker_done` flips it to `completed` (or it is
manually reset). To re-dispatch to a new terminal you must first
`task-update --id <task_id> --status ready`, then `dispatch`. Likewise, if a
worker reported `worker_done` prematurely (task flipped to `completed` but work
is unfinished), you must reset to `ready` before dispatching again. The same
irreversibility (entry 5) makes dedup load-bearing: filtering `task-list` by
status hides rows you still need to compare against.

**How to tell.** The dispatch error names the task and states the rule
explicitly. For dedup, the trap is silent: an empty `--status ready` result does
not mean no task exists — it means no *ready* task exists. Completed, blocked, or
failed duplicates are invisible to that filter.

**What to do.** To re-dispatch: `task-update --id <task_id> --status ready`,
then `dispatch --task <task_id> --to <handle> [--inject]`. To dedup before
creating: `task-list --run <run_id> --json` (no status filter) and match on the
spec text. Apply the empty-list habit from the reading section — a filtered empty
result is never proof of absence.

**Stamp.** `(observed: Orca 1.4.13x, 2026-07-25)`

---

### 7. Flag names vary per subcommand; the error is self-documenting

**Symptom.** You assume the task identifier flag is the same across
`task-create`, `dispatch`, and `task-update`, guess wrong, and get
`Unknown flag`. Or you pass `--deps task_04bf…` (a bare id) and get
`Invalid --deps: must be a JSON array of task IDs`.

**Mechanism.** Each subcommand names its target differently (verified via
`--help` on Orca 1.4.176): `task-create` takes `--spec <text>` (with optional
`--task-title`), `dispatch` takes `--task <task_id>`, `task-update` takes
`--id <task_id>`, `task-list` takes no id (it filters by `--status`/`--ready`/
`--run`). `--deps` on `task-create` expects a JSON array, e.g.
`--deps '["task_04bf…"]'`; a bare id is rejected. The good news: the `Unknown
flag` error lists the subcommand's valid flags, so the correct form is in the
error message.

**How to tell.** Run `orca orchestration <command> --help`. The flags and their
value shapes are listed. The JSON-array requirement for `--deps` is not spelled
out in `--help` (the flag shows with no value hint); the rejection error states
it exactly.

**What to do.** On `Unknown flag`, read the error — it prints the valid flags
for that subcommand; do not carry flag names over from a sibling subcommand. For
`--deps`, pass a JSON array string: `--deps '["task_04bf…","task_7c2a…"]'`. When
in doubt, `--help` before you commit to a flag form.

**Stamp.** `(verified: Orca 1.4.176, 2026-08-09)` — the flag names, the absence
of a delete verb, and the `--deps` flag presence were checked via `--help`. The
JSON-array-only rejection of a bare id is an observed behavior
(Orca 1.4.13x, 2026-08-01), not reproduced here because triggering it requires a
write; it is called out as observed in the Mechanism field above.

---

## What is deliberately not here

- **Personal/host-specific traps** (keychain guards, a specific vendor's
  subscription or quota config, a broken setting on one machine). These do not
  generalize and do not belong in a public map.
- **Restatements of the official guide.** Anything `orca skills get
  orchestration` already covers is pointed at, not repeated.
- **Multi-vendor recipes and quota economics.** Out of scope; see
  `./roster.md#the-shape-of-one-role` (when present) for the *shape* of a roles
  table, not its contents.
- **Relay-era RPC blocking as a current trap.** The 300 s `orca.cli` timeout and
  the empty-`task-list` self-heal were observed on a transport that has since
  been retired. They are not listed as current entries; they survive only as the
  evidence base for the reading habits above. If you see the same shape on the
  current local-socket transport, treat it with the same habits and file a
  stamped pitfall.
