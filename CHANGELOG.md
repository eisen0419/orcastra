# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `tools/orca-auth` — read-only login-state preflight for the six agent-CLI
  seats (claude / codex / pi / opencode / cursor / grok). Runs each CLI's
  official headless status command (grok: degraded existence-only probe),
  reports OK / ATTN / MISSING / DEGRADED with the login command to run, and
  never touches credentials. `--roles` limits seats to a roles config and
  escalates required-but-missing seats; `--json` for scripting.
- `tools/test-auth.sh` — self-test against PATH-injected mock CLIs
  (33 assertions, incl. zero-credential argv checks).

## [0.1.1] - 2026-08-12

### Changed

- Re-checked every read-only-verifiable conclusion against **Orca 1.4.180** and
  appended that row to `docs/compat.md`, along with a section stating exactly
  what the round covered and what it deliberately did not. Stamps that required
  a mutating call to obtain — delivery loss, cold-start swallow, unsubmitted
  input, re-dispatch refusal, binding theft, contract-migration read-only
  degradation, and the `worker-release` payload — keep their earlier `observed`
  stamps rather than being bumped to a build they were not reproduced on.
- `pitfalls.md` entry 7 records a drift: `task-create --help` now prints
  `--deps <json_array>` in its usage line, so the array requirement no longer has
  to be learned from the rejection error. The old behavior is retained as a
  `historical` note for readers on an earlier CLI. The entry also now lists the
  adjacent `--display-name` / `--parent` / `--from` and `task-list --brief`
  flags.
- `pitfalls.md` entry 5 records the `orchestration reset`
  (`--all | --tasks | --messages`) verb. Per-task deletion is still absent, which
  is what the entry is about; the reset verb's semantics are explicitly
  unexercised, since confirming them requires a destructive write.
- `mechanics.md` §3 and §5 now cite the on-disk evidence directly: the
  `sleepingAgentSessionsByPaneKey` map, its per-record `providerSession`
  (`id` / `key` / `transcriptPath`), the uniform `state: working` even for
  records whose origin already quit, and the two-segment pane key. §3 also
  records that an `experimentalAgentHibernation` setting exists and that the map
  was populated while it was off — without asserting a causal link between them.

### Fixed

- Install path A now documents the HTTPS fallback. The `owner/repo` shorthand
  clones over SSH, which fails on a machine with no GitHub SSH key; the full
  HTTPS URL form clones over HTTPS. Both forms verified 2026-08-10.
- Removed a stray closing parenthesis in the README demo's version-stamp note.

## [0.1.0] - 2026-08-10

### Added

- Repository skeleton: MIT `LICENSE`, `.gitignore`, and both plugin manifests
  (`.claude-plugin/plugin.json` for the plugin itself, and
  `.claude-plugin/marketplace.json` so the repo can be added as a marketplace).
- English `README.md` with dual-reader layout (human intro + Claude bootstrap) and
  two installation paths (plugin install, bare symlink).
- `CONTRIBUTING.md` capturing the five design DNA principles, the three-tier
  version-stamp discipline (`verified` / `observed` / `historical`, so an honest
  "observed but not re-checked this round" never has to masquerade as
  `verified`), the desensitization scan, and the pitfall-report issue template.
- `tools/orca-doctor` read-only health check (app version, CLI attribution,
  runtime handshake, data integrity) with `tools/test-doctor.sh` self-test.
- `skills/orca-orchestrate/SKILL.md` entry point — under 4 KB, with every
  reference loaded on demand rather than up front — plus five references:
  `mechanics.md` (Orca's internal accounting model), `pitfalls.md`
  (symptom-driven trap map), `delivery-contract.md` (two-section receipts,
  required-read receipts, the five evidence-validation values, and what a brief
  must make explicit), `review-loop.md` (the L0/L1/L2 tier gate, the
  reviewer-independence spectrum with a clean-context session as its floor, and
  the closing rules), and `roster.md` with `config/roles.example.json` (how to
  name your own worker roles; Claude-only starting point).
- `docs/quickstart.md` — one supervised-worker loop end to end, walked against a
  live Orca before release.
- `docs/compat.md` — the version matrix every stamped conclusion points at.
