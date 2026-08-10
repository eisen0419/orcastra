# Mechanics: how Orca actually keeps the books

> This file only covers what the official guide does not. Read it first:
> `orca skills get orchestration`. The official guide is the source of truth for
> the orchestration API, message types, dispatch rules, and the Contract
> Migration story; nothing here restates it. What this file adds is the *internal
> accounting model* that lets you read anomalies correctly and tell a real signal
> from a fake one.

Orca tracks a lot of state that is never fully visible in the UI. The mental
model below is what a coordinator needs so that "the worker disappeared from the
sidebar" does not become a false diagnosis. Each section follows the same shape:
**mechanism** (how Orca records it) → **what you observe** → **implication**
(which intuition this breaks) → **stamp**.

A note on stamps: three tiers are used throughout this repo.

- `(verified: …)` — re-checked with a read-only probe this run.
- `(observed: …)` — carried from an earlier observation, not re-verified.
- `(historical: …)` — the trigger has since disappeared; kept as a warning.

## 1. Agent identification runs on three channels, not one

**Mechanism.** The official material mentions OSC title parsing as the way Orca
detects whether an agent CLI is working or idle. That is one of three
*identification* channels. The primary channel is an HTTP hook: Orca writes a
small hook script into the agent's global config, the agent fires events as it
runs, and the hook POSTs structured payloads (event name, tool ids, prompt,
worktree/pane attribution) to Orca's local HTTP server. (A native
extension/plugin API is just an implementation variant of this same channel —
a different way agents that expose one push the same kind of events; it is not
a separate identification channel.) The second channel is OSC title parsing —
the universal fallback that needs no cooperation from the agent and yields only
a coarse "working / idle" signal. The third channel is foreground-process
identity: the runtime directly queries the PTY's foreground process and
recognizes the agent CLI by what is running, with no hook and no title required.

Priority, roughly: **HTTP hook** (richest — tool names, precise state) → **OSC
title** (only "working / idle", inferred) → **foreground-process identity**
(silent last resort, present even with no hook and no title).

**What you observe.** An agent that has no dot next to it in the tab bar is a
plain shell, not a recognized agent. A pulsing dot means working; yellow means
waiting for your input; grey means idle. A Restart chip appears after the agent
process exits.

**Implication — "visible in the sidebar" ≠ "hook is wired".** A foreground agent
with no hook installed still shows up (and may still report working/idle via OSC
or the foreground-process identity channel), because detection has three layers
and only one needs to fire. So a green dot is *presence*, not *integration*. If
you dispatch to that agent, it will not be able to send `worker_done`, because
the lifecycle channel is exactly the hook you have not verified. Before relying
on lifecycle messages, confirm the hook path, not just the dot.
(verified: Orca 1.4.176, 2026-08-09)

## 2. `worktree ps --json` `agents[]` has two sources, not three

**Mechanism.** The agent rows that `orca worktree ps --json` (and the similar
sweeps a coordinator does) attach to a worktree summary come from **two** of the
three channels above: the hook snapshot (same source as the sidebar) and OSC
title as a fallback. The foreground-process identity channel — the third one
that lets the sidebar show an agent even with no hook and no title — **does not
feed `agents[]`**.

**What you observe.** A worker terminal that is plainly running an agent CLI may
still show an empty `agents[]` array in `worktree ps --json`, while the sidebar
shows the agent just fine.

**Implication — `agents[]` absent ≠ worker dead.** Only a *positive* `agents[]`
entry is trustworthy. A negative result proves nothing: the hook may simply be
unwired, or OSC may not have produced a title yet, while the process keeps
working. When you need to confirm a worker is alive, read the terminal directly
(`orca terminal read --terminal <handle> --json`) or check the task/dispatch
state, never the absence of an `agents[]` row. Caveat: a *positive* `read`
result is trustworthy, but a *negative* one (empty or a garbled fragment) proves
nothing — `read`/`preview` cannot see some agent TUIs, and the relevant upstream
issues are closed but not re-verified on this build, so do not treat an empty
result as evidence the worker is dead; fall back to the process table or
dispatch state instead.
(observed: Orca 1.4.17x, 2026-07; the two-source split is stable across recent
builds, but the exact row shape drifts — re-check before scripting on fields)

## 3. Closing a window is hibernation, not termination

**Mechanism.** Orca's process tree separates the *view* from the *PTY*. The
daemon is an independent process that outlives the main app and holds every PTY.
Closing a tab does not kill the PTY process chain (agent CLI → shell → login).
Instead the tab is removed from the session's tab map and a *sleeping* record is
written under a per-pane hibernation key, carrying the agent, a provider session
id, and a transcript path. When the runtime later reconciles and finds a live PTY
with no owning tab, it re-adopts the PTY into a fresh tab — so the window
"comes back on its own", content intact, because it is the *same process* being
re-attached, not a restart. Hibernation is not limited to a small allowlist of
agents; any agent that Orca can resolve a provider session pointer for may end up
in the sleeping map.

**What you observe.** You close an agent window; minutes later (often on
re-entering the worktree) it reappears with its full scrollback. `orca terminal
close --tab` on such a window returns `tab_not_found` even though `terminal list`
still shows the terminal — because the tab is gone but the terminal is not.

**Implication — "I closed it" ≠ "it stopped".** Closing is a view-level
operation. The agent process keeps running, keeps spending tokens, and keeps
holding the worktree. To actually stop a worker you must end the PTY session's
root process; killing the agent CLI alone is not enough, because the shell/login
beneath it keeps the PTY alive and Orca will re-adopt it as an empty shell.
Before you assume a dispatched worker is gone, check the process table, not the
tab bar.
(verified: Orca 1.4.176, 2026-08-09 — the sleeping map and the live-PTY-with-no-tab
reconciliation are both present in the on-disk session file this run)

A corollary worth stamping: the supervised-worker path (`worker-start`) and bare
`dispatch` differ at the phenomenon level. A closed supervised window stays
closed; a closed bare-`dispatch` window regrows, because its sleeping record is
left in the live/working state and is re-adopted on every reconciliation. The
exact trigger that clears the supervised record is not pinned down — do not
assume it is "on completion" or cite any timing for it. This is the mechanical
reason "prefer supervised workers" is not just style.
(observed: Orca 1.4.176, 2026-08-07)

## 4. The terminal's authoritative model lives in the backend

**Mechanism.** The terminal you see in the renderer is a disposable view. The
authoritative model — a headless terminal emulator holding the full scrollback
and current state — lives in the daemon. The renderer's xterm is rebuilt from
that model whenever the tab is re-shown, the window is restored, or the renderer
is reloaded. State is also persisted to disk under the Orca application support
directory so it survives a daemon or app restart.

**What you observe.** After a crash or restart, terminal contents reappear. A
tab that looked blank when you switched back to it repopulates once the backend
reconnects. `orca terminal read` can return content for a terminal whose visible
pane looks empty.

**Implication — "it's gone from the screen" ≠ "the data is gone".** Treat the
visible pane as a cache that can be wrong or stale. When a worker's output looks
missing or garbled, the model almost certainly still has it; query the backend
(`terminal read`) or the on-disk history before concluding the worker lost
output. The reverse is also true: an empty-looking pane is not evidence the
worker is idle — it may simply be that the view has not caught up.
(verified: Orca 1.4.176, 2026-08-09)

## 5. Handles rotate; the pane key is the stable identity

**Mechanism.** A terminal handle (`term_…`) is runtime-scoped metadata, not a
durable identity. Reconnections, relaunches, and some lifecycle events reissue
handles. The durable key is the *pane key* — a `tabId:leafId` pair that survives
handle rotation within a session. The runtime records handles in a handshake
file on disk, and the handle an agent sees in its environment may be a stale one
from before a rotation.

**What you observe.** A handle you cached an hour ago now returns "not found".
`terminal list` shows the same pane under a new handle. The environment variable
holding the handle disagrees with the value `terminal list` reports for the
current pane.

**Implication — "handle not found" ≠ "process dead".** A stale handle is a
routing problem, not a death certificate. Resolve the current handle from the
stable pane key (or from `terminal list`) before retrying; caching a handle
across time and then treating lookup failure as a crash is a classic false
alarm. For self-identification inside a worker, read the pane key, not the
handle.
(observed: Orca 1.4.17x, 2026-07; the rotation-on-reconnect trigger is now
dormant on a pure-local setup since the SSH relay path was retired, but
intra-session rotation still occurs. Treat the "stale handle" failure mode as
live.)

## 6. Run identity, ownership, and lifecycle

**Mechanism.** A Run is a namespace and a coordinator inbox — it never schedules
or places workers. The terminal that creates a Run becomes its coordinator, and
that binding is **exclusive**: only one live coordinator terminal owns the Run's
write authority at a time. Worker lifecycle messages (`worker_done`, `heartbeat`,
`ask`) route to the Run bound to the active Dispatch. Read operations
(`task-list`, `run-show`) are not bound to the coordinator; writes
(`task-update`, dispatch injection, some terminal mutations tied to the Run) are.

**What you observe.** Two coordinator sessions pointing at the same Run will
silently steal the binding from each other. The session that lost the binding
can still *read* state, but its next *write* is rejected with an error naming the
Run. Re-binding (`run-use --id <run>`) from the displaced terminal restores
writes — until the other session writes again.

**Implication — a write rejection is not a connection failure.** When you see a
"not the coordinator of this Run" error, do not diagnose a dead socket or a
wedged runtime: read calls still work, which proves the channel is fine. Re-bind
and retry; if contention is ongoing, treat `run-use` as a routine preamble
before each write rather than an incident.
(observed: Orca 1.4.17x, 2026-08)

### Contract migration and the ownerless adopted Run

When Orca updates across a contract boundary, it adopts the pre-update
orchestration state into a fresh ordinary Run whose objective is
`Recovered orchestration work from a contract update`. That adopted Run's
coordinator handle is empty — it has no owner. By design the runtime is
**fail-closed** here: no process can prove it is the original coordinator, so
all writes on the adopted Run are rejected and it degrades to read-only
inspection. The official guide's *Contract Migration* section is authoritative
for the recovery labels (`[LEGACY COMPATIBILITY]`, `[LEGACY READ-ONLY]`, …) and
the takeover command; read it for those mechanics.

**What you observe.** After an update, your pre-update tasks are visible but
immutable: `task-update` and `dispatch` are refused, while `task-list --run
<adopted>` and `run-show` work. Sub-commands of `orchestration` invoked *without*
`--run` may be refused outright with a "could not prove original process
identity" message, while the same calls with an explicit `--run` succeed for
reads.

**Implication — a refused write after an update is not a bug in your flow.**
The frozen queue is not repairable in place; the documented path is to abandon
it and recreate the work in a fresh current Run. Do not spend time trying to
"un-stick" an adopted Run by reissuing writes or reconnecting — the runtime is
behaving correctly. (Pointer only: full recovery semantics live in the official
guide.)
(observed: Orca 1.4.138-rc.7, 2026-07-31; the fail-closed read-only behavior is
by-design and stable. The takeover mechanics are documented upstream; do not
treat any single failed takeover attempt as proof of a mechanism.)

### The in-repo run-id convention

**Mechanism (convention, not tooling).** Because a Run id must be passed to
nearly every orchestration write, coordinators in this project's lineage keep the
current Run id in a single gitignored file at the repo root (e.g. `.orca-run`),
holding the id as its first non-comment line. That file is the single source of
truth for "which Run am I bound to" within a working tree. It is deliberately
*not* committed: a Run id is local orchestration state, not project history, and
committing it would leak one developer's session identity into the shared tree.

**What you observe.** A fresh clone or a `git clean -fd` has no such file, even
though the repo otherwise looks complete. Tools that read the Run id from it
fail loudly (exit non-zero) when the file is missing or malformed, rather than
guessing by creating a new Run.

**Implication — a missing run-id file is expected after a clean checkout, not a
corruption.** Recover by re-adopting an existing Run id — list the candidates
with `orca orchestration run-list` and rebind with
`orca orchestration run-use --id <run_id>`, never by creating a new Run
(`orca orchestration run-create`) — creating a new Run from a "missing file"
error is exactly how you split your task queue. This file is a convention;
automation around it is out of scope for this release.
(observed: Orca 1.4.17x, 2026-08)

## How to use this model

When something looks broken, run the failure through these six intuitions before
reaching for a restart:

- Visible ≠ wired (§1). Check the hook path, not the dot.
- Absent `agents[]` ≠ dead (§2). Read the terminal or the task state.
- Closed ≠ stopped (§3). Check the process table.
- Empty screen ≠ lost data (§4). Query the backend model.
- Handle not found ≠ dead (§5). Re-resolve from the pane key.
- Write refused ≠ broken runtime (§6). Re-bind, or it is a frozen adopted Run.

For symptom-driven recovery (what to do when one of these *does* bite), see
`./pitfalls.md`. This file stays on the *how it works* side; that one is the
*what to do* side.
