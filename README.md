# orcastra

Production-grade coordination practices for running **Claude Code as an Orca
orchestration coordinator**.

Orca's official guide (`orca skills get orchestration`) tells you what the
API *is*. orcastra teaches your Claude Code how to *run a reliable coordinator
loop*: verify delivery, close out idempotently, review independently, and know
where the traps are on the map.

> **Status:** `0.1.0` — first release. Every behavioral claim carries a version
> stamp; see [`docs/compat.md`](./docs/compat.md) for the Orca versions these
> were checked against, and [CHANGELOG.md](./CHANGELOG.md) for what shipped.

## What it is

You already use Orca + Claude Code and want to graduate from "open one terminal,
paste a prompt" to a coordinator that *dispatches work to workers and closes it
out* — without guessing whether the task arrived or finished. orcastra is that
practice pack: a thin skill, a pitfalls map with version stamps, a delivery
contract, and a doctor that checks your environment.

It is **not**:

- a restatement or mirror of the official Orca docs (those drift; we point at
  them and write only what they leave out),
- a general multi-agent framework (it serves the Orca runtime only),
- a "how to install Orca" guide (we assume `orca terminal list` already works).

## 30-second demo

A coordinator session, fictional but representative:

```
$ orca orchestration run-create --objective "land feature X"
run_8f3a...                       # run created; this terminal is its coordinator

$ orca orchestration task-create --run run_8f3a... --task-title "write tests for A"
task_04bf...                      # ready task

$ orca orchestration worker-start --task task_04bf... \
      --worktree current --agent claude --run run_8f3a...
dispatched → ctx_803a...  (stage: input_accepted)   # delivery OBSERVED, not inferred
```

*(verified: Orca 1.4.176, 2026-08-09) — each verb above was confirmed against
`orca orchestration --help`; `run-create` creates the Run and binds the invoking
terminal as its coordinator (worker-terminal binding happens later, at
`worker-start --run`).)*

The worker runs in its own terminal. When it finishes it sends `worker_done`.
The coordinator does **not** trust that signal alone — it reads the worker's
report, re-verifies the claim, and only then marks the task complete via
`task-list`. That verify-then-close discipline, not the dispatch itself, is what
orcastra teaches.

## Install

### A) As a Claude Code plugin (recommended)

```bash
claude plugin marketplace add eisen0419/orcastra
claude plugin install orcastra@orcastra
```

Restart Claude Code. The `orca-orchestrate` skill becomes available and loads on
demand.

### B) Bare symlink (no plugin infrastructure)

```bash
git clone https://github.com/eisen0419/orcastra ~/orcastra
ln -s ~/orcastra/skills/orca-orchestrate ~/.claude/skills/orca-orchestrate
```

The skill is picked up by Claude Code's skill loader. This path is the fallback
when the plugin marketplace is unavailable.

> Both paths assume the `skills/orca-orchestrate/` directory exists. It does —
> the skill entry and its `mechanics.md` / `pitfalls.md` references are in the
> tree. Note that the bare-symlink path links only that directory, so anything
> the skill points to outside it (`docs/quickstart.md`, `tools/orca-doctor`) is
> read from your clone, not through the symlink.

### Verify your environment

```bash
~/orcastra/tools/orca-doctor     # checks Orca version, CLI resolution, runtime handshake
```

`orca-doctor` ships with this repository. It reports all-green, or
states plainly what is missing (Orca not installed / runtime unreachable /
profile corrupted) — it never reports success on a dead runtime.

## Bootstrap for your Claude Code

If you are a Claude Code instance reading this, the user wants you to set
yourself up as an Orca coordination assistant. Do this:

1. **Clone this repo** to a stable path, e.g. `git clone
   https://github.com/eisen0419/orcastra ~/orcastra`.
2. **Install the skill** via one of the two paths above (plugin install or bare
   symlink into `~/.claude/skills/`). The skill is the thin entry point; its
   `references/` are loaded only when a coordination task calls for them.
3. **Run the doctor**: `~/orcastra/tools/orca-doctor`. Treat any non-green
   output as a precondition failure — do not attempt orchestration until it is
   resolved.
4. **Load the official API** on demand, not eagerly: `orca skills get
   orchestration` and `orca agent-context`. orcastra complements these; it does
   not replace them.
5. **Before your first dispatch**, read `skills/orca-orchestrate/SKILL.md` (the
   entry, ≤ 4 KB) and, only if the task needs it, the referenced pitfalls and
   delivery contract.

Coordinate fail-closed: if you cannot *verify* delivery, do not *infer* it.

## Non-goals

- **Not an Orca docs mirror.** Official content is linked, never restated.
- **Not a general multi-agent framework.** Orca runtime only.
- **No install/setup tutoring for Orca itself.** `orca terminal list` working is
  the entry assumption.

## License

MIT. See [LICENSE](./LICENSE).
