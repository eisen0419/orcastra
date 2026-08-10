# Building a worker roster

A roster turns dispatch choices into named, repeatable roles. Without one, every
new task starts with the same questions: who should do it, which command should
start them, and whether their work can be observed afterwards. The answers then
drift from task to task, leaving historical commands inconsistent. A short table
makes those choices explicit and reusable.

## The shape of one role

Keep one entry per stable role. The example in `config/roles.example.json` uses
these same keys:

| Key | Record |
| --- | --- |
| `id` | A stable dispatch name. Keep it when the model generation changes; update the entry rather than every reference to it. |
| `command` | The complete startup command, including explicit `--model <model-id>` and `--effort <reasoning-level>` arguments. This is the string passed to the terminal-creation step in the repository's `docs/quickstart.md`. The `--command` input is supported by the current Orca terminal-create interface (verified: Orca 1.4.176, 2026-08-10). |
| `observability` | A tier such as `readable`, `limited`, or `unknown` describing whether the worker transcript is expected to be readable. Record the result, because it determines how well a failure can be diagnosed. |
| `work_type` | One sentence about the shape of work this role fits, such as implementing a scoped change or reviewing a proposed change. This is a routing description, not a quality ranking. |
| `session_dir` | The directory where this agent's session or transcript lands. Use it to check whether a worker received the task; replace the neutral example path with the path used by your setup. |
| `verified_on` | The date on which you last checked the command and observability entry. |

Do not rely on an agent's global default configuration. Global defaults are
mutable state: another change can alter them silently, while an explicit command
records the model and reasoning choice alongside the role (observed: Orca 1.4.176, 2026-08-07). Replace the placeholders in `command` before starting a
worker; never omit either explicit argument.

The roster is a human- and coordinator-readable checklist, not a configuration
format consumed by dispatch automation. Keep the session path and observability
tier factual, and use `unknown` until they have been checked.

## Start with two Claude roles

The smallest useful roster has two entries: one `implementer` and one
`reviewer`. The reviewer must not be the implementer for the same change; the
review loop defines that independence rule in
`./review-loop.md#reviewer-independence-a-graceful-spectrum`.

`config/roles.example.json` is a Claude-only starting point. Copy its shape,
replace the placeholders with values available in your environment, and keep
the two role IDs stable. Agent installation and permission-mode setup are
outside this roster; use the agent's own setup guidance.

## Add another provider later

Multiple providers are optional. The benefit of adding a second one is a chance
for blind spots not to overlap, not a claim that one provider is better. When
adding one, append a role with a new stable `id`, a complete command with
explicit model and reasoning arguments, an observed `observability` tier, a
`work_type`, a `session_dir`, and `verified_on`. Do not turn the table into a
model comparison, subscription plan, quota plan, or scorecard.

## Keep it current

After an Orca or agent CLI upgrade, recheck each role's command against the
current `--help` output and recheck transcript access, then update only the
affected entry and its `verified_on` date. The official orchestration skill is
the API source of truth; this table records your local, repeatable choices.
