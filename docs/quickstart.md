# Quickstart: your first supervised worker

This walks a stranger through dispatching one toy task to a supervised worker
and closing it out — without guessing whether the task arrived or finished.

The toy task has no side effects beyond the worktree and needs no language
stack: the worker writes one plain-text file with a fixed string, and you
verify the bytes mechanically.

> **Read this first.** The authoritative API is the official Orca skill — run
> `orca skills get orchestration` and `orca agent-context` on demand. This doc
> teaches the *order and the judgment calls* for one successful loop; it does
> not restate flags. Where Orca behavior is asserted, it carries a version
> stamp (see `../CONTRIBUTING.md#version-stamp-discipline`). Three tiers:
> `(verified: …)` = re-checked with a read-only command this round;
> `(observed: …)` = carried from an earlier field observation, not re-verified
> here; `(historical: …)` = the trigger has since disappeared.

## 0. Prerequisites

You already use Orca + an agent CLI (Claude Code is used below) and `orca
terminal list` returns a list, not a connection error. If it does not, fix Orca
first — this kit does not tutor Orca installation.

```bash
orca terminal list --json          # must return a list
./tools/orca-doctor                # all-green, or it says plainly what's missing
orca worktree list --json          # your working directory must be inside one of these
```

The worker in this walkthrough runs on your **local** `current` worktree.
SSH / remote-server hosts behave differently and are out of scope here.

> **The third check is the one people trip on.** `--worktree active` in step 3a
> means "the Orca-managed worktree that contains my current directory" — not
> "whatever is selected in the Orca window". If you cloned this kit somewhere
> Orca does not manage, step 3a fails with
> `selector_not_found: No Orca-managed worktree contains the current directory`.
> Register the folder first — either from the CLI, or by opening it as a project
> in the Orca app:
>
> ```bash
> orca repo add --path /absolute/path/to/your/project --json
> ```
>
> `(verified: Orca 1.4.176, 2026-08-10)` Then run this walkthrough from inside a
> managed worktree.

## 1. Create a run

A Run is the namespace and coordinator inbox for the whole loop. The terminal
that creates a Run becomes **its coordinator**, and that binding is
**exclusive**: a second session that re-binds the same Run will break the first
session's later writes. `(observed: Orca ~1.4.16x, 2026-08-04)` So create the
Run from the terminal you intend to coordinate from.

```bash
orca orchestration run-create --objective "quickstart: first supervised worker" --json
```

Expected (fictional):

```
{
  "id": "<request-uuid>",
  "ok": true,
  "result": { "run": { "id": "run_8f3a...", "objective": "...", ... } },
  "_meta": { ... }
}
```

**Every RPC reply in this walkthrough is wrapped in this envelope** — the
orchestration, terminal, and worktree commands all use it. (Local introspection
commands such as `orca agent-context --json` do not.) The id you want is at
`.result.run.id`; the top-level `.id` is the *request* id and looks nothing like
a Run id. `(verified: Orca 1.4.176, 2026-08-10)` To keep this walkthrough
readable, every later "Expected" block shows only the `result` payload.

Save the `run_…` id. If you see something else →
`../skills/orca-orchestrate/references/pitfalls.md`.

## 2. Create a task

A Task is the work item; creating it does not dispatch it. Keep the spec short
and self-verifiable — long specs are a known friction point, not a feature.

```bash
orca orchestration task-create \
  --run run_8f3a... \
  --task-title "write greeting file" \
  --spec "Write the file quickstart-greeting.txt in the worktree root with exactly the content 'hello from worker' (no extra lines). Then send worker_done with --outcome succeeded and --files-modified quickstart-greeting.txt." \
  --json
```

Expected `result` payload (fictional):

```
{ "task": { "id": "task_04bf...", "status": "ready", ... } }
```

If you see something else → `../skills/orca-orchestrate/references/pitfalls.md`.

## 3. Start the worker (two steps)

We start the agent terminal **first**, then register it as a supervised worker.
This is deliberate: `worker-start --agent <a>` without `--model` launches the
agent with its own configured default provider/model, which may not be the
quota you want to burn. `(observed: Orca 1.4.176, 2026-08-07)` Creating the
terminal yourself keeps provider/model choice in your hands — you pass whatever
argv you want to `terminal create`, then hand the handle to `worker-start`.

**Step 3a — open the agent terminal:**

```bash
orca terminal create --worktree active --title "greeting-worker" --command "claude" --json
```

Expected `result` payload (fictional):

```
{ "terminal": { "handle": "term_1c2d...", ... } }
```

`--worktree active` / `--command` / `--title` are the relevant flags here.
`(verified: Orca 1.4.176, 2026-08-09)` Wait for the agent TUI to be idle before
dispatching (see the official skill's `terminal wait --for tui-idle`).

**Step 3b — register it as a supervised worker:**

```bash
orca orchestration worker-start \
  --task task_04bf... \
  --terminal term_1c2d... \
  --run run_8f3a... \
  --json
```

`--terminal` (reuse an existing terminal) cannot combine with `--model`; that
is why provider choice is settled in step 3a, not here.
`(verified: Orca 1.4.176, 2026-08-09)` If you see something else →
`../skills/orca-orchestrate/references/pitfalls.md`.

## 4. Confirm delivery

Do not infer delivery from "the terminal looks busy." Read the `worker-start`
receipt: a `ready` state with `stage: input_accepted` is **runtime-level**
delivery confirmation — observed, not inferred. `(observed: Orca 1.4.176,
2026-08-07)` That is the "not guessing" checkpoint for this step.

```bash
orca orchestration worker-show --dispatch <dispatch_id> --json
```

Expect `state: ready`, `stage: input_accepted` (the dispatch id comes from the
`worker-start` receipt). If `stage` is not `input_accepted`, the task did not
reach the worker — see `../skills/orca-orchestrate/references/pitfalls.md`
before retrying.

## 5. Wait for the worker

Do **not** teach yourself to "wait for the `worker_done` push." That
notification is routed by the Run binding; if the binding is stolen or the
worker handle rots, the push silently drops and you would wait forever.
`(observed: Orca ~1.4.16x, 2026-08-05)` Collect completion through a
**binding-independent** channel instead:

1. **Disk sentinel (primary).** Have the worker write a `.DONE` file (or, here,
   the `quickstart-greeting.txt` file itself) as its last action, then poll the
   filesystem.
2. **`task-list --run` polling (backup).** A valid `worker_done` flips the task
   to `completed` automatically, and `task-list --run <run_id>` reads state
   without depending on any binding.

Never leave the poll open-ended: a worker that dies or loses its window will
never write the sentinel, and an unbounded loop will spin forever. Fail closed —
give the wait a deadline and exit non-zero when it trips.

```bash
# primary: the file's existence is the worker's own last-action signal.
# Bound the wait at 75 min — past the 15–60 min a healthy task takes — so a
# trip means the worker hung or its window died, not "still working."
deadline=$(( $(date +%s) + 75 * 60 ))
while [ ! -f quickstart-greeting.txt ] && [ "$(date +%s)" -lt "$deadline" ]; do
  sleep 10
done
if [ ! -f quickstart-greeting.txt ]; then
  echo "timed out waiting for worker sentinel" >&2
  exit 1  # worker hung or window died -> pitfalls
fi

# backup: confirm the task itself settled
orca orchestration task-list --run run_8f3a... --json
```

Expected (fictional): the file appears, and the task row shows
`status: completed`. A long task may legitimately run 15–60 minutes, so the
75-minute ceiling sits above that range on purpose — a trip is a real failure,
not impatience. If you see something else →
`../skills/orca-orchestrate/references/pitfalls.md`.

## 6. Verify, then close

The worker's `worker_done` self-report is **not trustworthy** for decisions:
re-run the acceptance check yourself and read the worker's output before
marking anything done. `(observed: Orca ~1.4.16x, 2026-08-05)`

```bash
# the toy acceptance check — mechanical, no judgment needed
test "$(cat quickstart-greeting.txt)" = "hello from worker" && echo OK || echo FAIL

# read what the worker actually did
orca orchestration worker-read --dispatch <dispatch_id> --json
```

Only when the check prints `OK` and the transcript reads sensibly is the task
truly done. A valid `worker_done` already flipped the task to `completed`
automatically — do **not** follow it with `task-update --status completed`
unless you are explicitly overriding. If you see something else →
`../skills/orca-orchestrate/references/pitfalls.md`.

## 7. Clean up

Release the dispatch once it has settled, then close the terminal yourself.
`worker-release` never closes a terminal it did not create — and in this
walkthrough it did not, because **you** created it in step 3a.

```bash
orca orchestration worker-release --dispatch <dispatch_id> --json
```

Expected `result` payload (fictional):

```
{ "state": "retained", "reason": "external_terminal",
  "processAction": "none", "archive": null }
```

`retained` is the **correct** outcome here, not a failure: the two-step start in
step 3 is exactly what makes the terminal "external", so release deliberately
leaves it running and archives nothing. Close it yourself:

```bash
orca terminal close --terminal term_1c2d...
```

`worker-read` keeps working after release on this path anyway — verified with
`archive: null`, transcript still readable.
`(verified: Orca 1.4.176, 2026-08-10)` If you see something else →
`../skills/orca-orchestrate/references/pitfalls.md`.

---

You have now run one full supervised loop: create a Run, create a Task, start a
worker in two steps, confirm delivery from the receipt, collect completion via
a binding-independent channel, verify the work yourself, and release the
terminal. The rest of this kit — `../skills/orca-orchestrate/references/` —
exists for when a step does not look like the expected output above.
