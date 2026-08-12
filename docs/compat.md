# Orca compatibility

This matrix records the Orca App versions used to check this repository's
conclusions. Every stamped conclusion implicitly points here: compare your Orca
version with the closest row to estimate whether it still applies.

| Orca App | Checked | Scope |
| --- | --- | --- |
| 1.4.176 | 2026-08-10 | Repository documentation |
| 1.4.180 | 2026-08-12 | Read-only re-check: `orchestration` + `terminal` verb flags, RPC envelope shape, on-disk hibernation map, doctor path layout |

After checking a new version, append a row; do not rewrite historical rows.
Read `observed` and `historical` stamps as pointers to earlier rows; see
`../CONTRIBUTING.md#version-stamp-discipline` for the three-tier definitions.

## What the 1.4.180 round covered

A round's scope is part of its evidence: a row above does not mean every
conclusion in the repository was re-checked on that build. The 1.4.180 round
used only read-only probes — `<verb> --help`, `--json` reads, and reading the
on-disk profile data file — and therefore re-checked only the claims those
probes can reach:

- **Re-checked and still true.** Verb flag names and value shapes across
  `orchestration` and `terminal`; the absence of any task delete/cancel verb;
  the `task-update --status` value set; the RPC envelope (`id` / `ok` /
  `result` / `_meta`) and that `agent-context --json` is not wrapped in it;
  `worker-start`'s refusal to combine `--terminal` with `--model`; the
  per-pane sleeping-agent map and the two-segment pane key; the doctor's
  path layout.
- **Re-checked and drifted.** `task-create --help` now spells out
  `--deps <json_array>` in its usage line, so the flag's value shape no longer
  has to be learned from the rejection error. See `pitfalls.md` entry 7.
- **Newly recorded.** An `orchestration reset` verb exists with
  `--all | --tasks | --messages`. Its semantics were **not** exercised: doing so
  is a destructive write. See `pitfalls.md` entry 5.
- **Not re-checked.** Every conclusion whose trigger requires a mutating or
  destructive call — delivery loss, cold-start swallow, unsubmitted input,
  re-dispatch refusal, binding theft, contract-migration read-only degradation,
  and the `worker-release` payload. Those keep their earlier `observed` stamps
  by design; reproducing them on a live orchestration is disruptive.
