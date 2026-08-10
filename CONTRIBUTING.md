# Contributing to orcastra

orcastra is a clean-room distillation of practices for running Claude Code as a
reliable Orca orchestration coordinator. Contributions are welcome, but they
must fit the project's character: thin entry points, version-stamped conclusions,
and no drift-prone prose that duplicates the official Orca guide.

## The five DNA principles

Every contribution should be checkable against these five. If a change violates
one, it probably does not belong here.

1. **Progressive disclosure.** Entry points stay thin (`SKILL.md` ≤ 4 KB).
   Details live in `references/` and are loaded on demand, not eagerly. The
   passive-load budget (manifest + entry skill) is ≤ 6 KB. If you are tempted to
   grow the entry, ask whether the content belongs in a reference instead.

2. **Executable self-description over prose.** Command-line behavior is
   documented by pointing at `--help` and the official Orca skill
   (`orca skills get orchestration`, `orca agent-context`), not by restating
   flags in prose. Prose keeps only the conclusion, the version stamp, and the
   *why*. This is a direct defense against Orca's drift speed (thousands of
   commits per month).

3. **Every conclusion carries a version stamp.** Choose one:

   - `(verified: Orca 1.4.176, 2026-08-10)` — a read-only re-check performed
     this round.
   - `(observed: Orca <version>, <date>)` — an earlier observation not
     re-checked this round.
   - `(historical: <version/date>; <why it may no longer apply>)` — a trigger
     that disappeared; retained as a historical record.

   An Orca behavioral conclusion without a stamp is not mergeable. Three tiers
   leave room for honest evidence: many conclusions come from earlier
   observations, while reproducing them can be destructive and contaminate a
   live orchestration. If you cannot safely re-check, use `observed` rather
   than claim `verified`.

   On re-check, keep a claim current only if it still holds. If it does not,
   prefer `historical` and explain why, since readers may be on an older Orca.
   Delete a historical entry only when it no longer helps any supported reader
   and its context is no longer actionable; otherwise retain it. See
   `docs/compat.md` as the canonical version matrix.

4. **Fail-closed by example.** Every example and tool in this repo errors and
   stops when unsure, rather than silently degrading. This is both a tool-design
   rule and a teaching one: the examples are the curriculum. Prefer an explicit
   error over an inferred success.

5. **Clean room.** This repo grew from an empty commit. Every line is written
   for this repo — never copy in proprietary or non-public material, and never
   paste large blocks from anywhere. When a tool has to match another program's
   behavior, reproduce the *constraint* by describing it rather than lifting the
   implementation, and derive self-tests from this repo's own spec instead of
   importing a suite. Cite only sources a reader can reach.

## Version-stamp discipline

- Stamp **every** behavioral claim about Orca with the App version and the date
  you verified it, using the format above.
- Re-verify before changing a stamp. Do not bump a stamp to a version you have
  not actually run.
- Orca-specific CLI flags, RPC shapes, and file locations drift fastest; stamp
  them even when you are "just" copying a command. The official skill
  (`orca skills get orchestration`) is the source of truth for current API —
  point at it rather than restating it.
- The compatibility matrix in `docs/compat.md` is the aggregate view. When you
  add or refresh a stamp, make sure `compat.md` still agrees.

## What does not belong here

- **Restatements of the official Orca guide.** That is a drift body. Link to it
  (`orca skills get orchestration`) and write only what it does *not* cover.
- **Multi-vendor recipes** (subscription economics, quota tactics, per-model
  quality profiles). Too personal and too volatile. `roster.md` gives the *shape*
  of a roles table, not the contents.
- **Personal paths, hostnames, tokens, or pairing details.** Run the
  desensitization scan (see *Desensitization scan* below) before publishing;
  examples must use fictional identities and paths.

## Reporting a pitfall

Pitfalls live in `references/pitfalls.md` and are the project's long-term moat.
If you hit a behavior that surprised you and cost real time, file an issue using
the template below so it can be distilled (clean-room) into the pitfalls map.
Every field is required; an unstamped pitfall will be closed.

```markdown
### Symptom
What you observed, in one or two sentences. The user-visible failure, not your
hypothesis.

### Mechanism
What actually caused it, once you confirmed the root cause (file:line or RPC
shape if you have it). If you only have a hypothesis, say so and mark the issue
"unconfirmed".

### Evidence
The minimal reproduction or observation that distinguishes this cause from
look-alikes. Paste commands and outputs with fictional identities substituted
for any real paths/tokens.

### Orca version
The App version and date you reproduced it on, e.g.
`Orca 1.4.176, 2026-08-09`. Required.
```

## Desensitization scan

Before requesting review (and before any publish), run this scan from the repo
root. It covers the generic leakage categories: email addresses, absolute home
directory paths, IP literals, and token/secret/api-key assignments. The `-i`
flag makes it case-insensitive so `Secret`/`TOKEN`/`ApiKey` are not missed.

```bash
# Intentionally impersonal: add your own username / machine name / identity
# to the pattern before running. No real name or email is used as an example.
# Categories (single combined regex so grep sees one pattern, not many files):
#   email addresses | absolute home dirs | IPv4 literals | token/secret/api-key assignments
grep -riInE --exclude-dir=.git '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}|/Users/|/home/|([0-9]{1,3}\.){3}[0-9]{1,3}|(token|secret|apikey|api_key|password|passwd|bearer)[[:space:]]*[:=]' .
```

Expected output on a clean tree: no matches, or only matches on the in-repo
exempt list (record each exemption with a one-line reason in the PR
description). Any non-exempt match blocks merge.

## Pull requests

- Branch from `main`, conventional-commit messages in English
  (`feat:`, `docs:`, `fix:`, `chore:`).
- Keep the passive-load budget in mind; if your PR grows `SKILL.md` or
  `plugin.json`, justify it in the PR description.
- Run the desensitization scan (see *Desensitization scan* above) before
  requesting review and paste the output. Non-exempt matches block merge.
- At least one independent review (different session, or different vendor) is
  required before merge. The reviewer's brief should name "leakage and personal
  residue" explicitly.
