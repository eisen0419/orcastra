# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Install path A now documents the HTTPS fallback. The `owner/repo` shorthand
  clones over SSH, which fails on a machine with no GitHub SSH key; the full
  HTTPS URL form clones over HTTPS. Both forms verified 2026-08-10.

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
