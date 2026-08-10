# Delivery contract

Use this contract when a delegated task is substantial enough to require a
written brief, an evidence-backed result, and a coordinator decision. It
covers two moments: what must be true before assignment, and what a worker
must return. It is a format and evidence discipline for people and agents,
not a command interface. The review procedure that consumes these fields is
described in `./review-loop.md`.

## Right scale and exceptions

Do not apply this contract to a seconds-long lookup, a one-sentence answer, or
a purely mechanical conversion whose result is self-evident. Use it when
there is meaningful judgment, a non-trivial change, or a result that another
person must be able to accept or reject mechanically.

## 1. Split every substantial receipt in two

The worker's report has exactly two top-level sections:

1. `<control>` is strict JSON. It contains the machine-readable decision,
   acceptance evidence, required-read receipts, deviations, and other
   accounting fields.
2. `<analysis>` is prose. It contains reasoning, evidence, limitations, and
   context for human review.

The coordinator decides from `<control>`; `<analysis>` is for checking the
load-bearing evidence and understanding the decision. The split is deliberate:
conclusions must be machine-readable for automation, while reasoning must be
human-readable for verification. Mixing them forces a person to extract
decisions from prose, which makes omissions and inconsistent judgments easy.

`<control>` must contain one JSON object and nothing else: no Markdown fence,
comments, trailing commas, or prose. A minimal shape is:

```json
{
  "verdict": "DONE",
  "acceptance": [
    {"id": 1, "status": "pass", "evidence": "..."}
  ],
  "requiredReads": [
    {"file": "docs/design.md", "keyEvidence": "Lines 18-24: ..."}
  ],
  "deviations": [],
  "branch": "feature/example",
  "head": "abc1234",
  "bytes": 0,
  "stamps": {"verified": 0, "observed": 0, "historical": 0}
}
```

`verdict` is `DONE` only when every acceptance item passes; otherwise use
`BLOCKED` and leave the blocking evidence in the summary. `acceptance.status`
is only `pass` or `fail`. Keep `branch`, `head`, and `bytes` factual. The
`stamps` counts summarize version-stamped runtime observations in the report;
they do not replace evidence-validation status.

## 2. Required reads are receipts, not acknowledgements

Before assignment, the brief lists the files or sources that shape the work.
At return, `<control>.requiredReads` contains one entry for every item. Each
`keyEvidence` must give a line or range, a distinctive passage, or an
observation plus its implication. Repeating a filename or heading is not
evidence.

This protects against the most expensive kind of rework: a worker says it read
the governing material, acts on an unstated assumption, and only the review
finds that the source was never understood. A missing entry or vague evidence
is a failed receipt, even if the artifact looks plausible.

## 3. Use five values for evidence validation

Use these values only for the status of an evidence-backed conclusion:

- `verified`: the cited source and the stated method support the conclusion.
- `partially_supported`: only part of the conclusion is supported. It never
  counts as `verified`.
- `unsupported`: the available evidence does not support the conclusion.
- `conflicting`: relevant evidence disagrees; name the conflict.
- `verification_blocked`: the check could not be completed. This is not a weak
  pass. Keep it in the summary until someone decides how to resolve it.

Do not use these values for disposition fields such as `KEEP`, `DROP`, or
`READY`. Evidence status says what is known; disposition says what to do.

## 4. A brief must make four things explicit

### Ground facts

Give environmental and contextual assertions their own section. Mark every
row as either:

```text
verified — the fact, plus the file read or probe that verified it
inferred — the current belief; the worker must pin it down before acting
```

An `inferred` row is not permission to treat a guess as established context.
The worker records the verification or the failure to verify it before relying
on the row.

### Imperatives still contain facts

An instruction such as “follow the X precedent” or “keep Y consistent” embeds
a factual assertion about X or Y. Imperative grammar does not bypass the
`verified`/`inferred` gate. The brief writer must verify the referenced
property. If that cannot be done, write the belief as `inferred` and tell the
worker to pin it down before following the instruction.

### The in-scope cost ledger

Attach the known negative list to the brief. Each entry is one of:

- `rejected`: explicitly outside the intended result;
- `deferred`: intentionally postponed to a named later decision or scope;
- `accepted-cost`: a known limitation accepted for this delivery.

An `accepted-cost` entry must state its ceiling, the condition that triggers
reconsideration, and an escalation path. A ceiling bounds the exposure or
quality trade-off; the escalation path says who or what reopens it. Without
those fields it is a permanent exemption, not a known cost.

Reviewers must not file a finding merely because an in-scope ledger entry
exists. They may mark `challenge` only when new evidence disputes the recorded
decision or its stated boundary.

### Non-functional requirements need a threat model and a tier

For each security, privacy, reliability, or performance requirement, state:

1. where the data flows;
2. who can read or observe it;
3. who can write into the protected surface and with what permissions; and
4. what happens if the data is exposed or changed.

The write-side question is mandatory: defenses are meaningful only relative
to the actor who can alter the protected surface. If no such actor exists,
write that explicitly.

Assign one tier:

- `hard`: required, review-blocking, and bounded by a defense ceiling. State
  the highest attacker capability covered and what is deliberately conceded
  above it. A `hard` requirement without a ceiling is an unbounded review
  budget, not a hard requirement.
- `cheap-insurance`: inexpensive protection that is welcome but does not open
  a review round or create a failure by itself.
- `non-goal`: explicitly out of scope; record it in the cost ledger so it is
  visible, and allow only a `challenge` backed by new evidence.

An un-tiered non-functional requirement is an incomplete brief, not an
implicit downgrade.

## 5. Deviations are mandatory

Every report includes `deviations`. An empty array means zero deviations. For
each departure from the brief, record exactly:

```json
{"where":"section or artifact location","what":"the departure","why":"the reason"}
```

Record a deviation when resolving contradictory instructions, changing an
assumption, or leaving a requested check incomplete. This is the worker's
safe channel for explaining a necessary departure, and often the brief
writer's own defect report: an internally inconsistent brief can force a
worker to deviate.

## 6. When a receipt is ready to review

A receipt is mechanically ready only when:

- the control section parses as one JSON object;
- every acceptance item has `pass` or `fail` plus concrete evidence;
- every required read has non-vacuous `keyEvidence`;
- all evidence uncertainty uses the five validation values without confusing
  them with a disposition;
- `deviations` is present and complete; and
- analysis explains the evidence, unresolved blocks, and material limits.

If one of these is absent, return the receipt for correction rather than
extracting a conclusion from the prose.
