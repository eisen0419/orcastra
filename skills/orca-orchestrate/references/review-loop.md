# Review Loop

This is the policy for judging a worker delivery after it arrives. The delivery
fields themselves are defined in
`./delivery-contract.md#1-split-every-substantial-receipt-in-two`; this document defines
the review depth, reviewer independence, repair rounds, and closing decision.

## Start with a tier gate

Review effort is a risk budget. A review gate that only ever adds work becomes a
tax of its own, so choose a tier from observable conditions rather than instinct:

| Tier | Use it when | Required path |
| --- | --- | --- |
| **L0 — self-validation** | The change is low-blast-radius and mechanically decidable: documentation, bookkeeping, or a one-off script whose acceptance can be stated as commands and outputs. | The dispatcher reads the diff and runs the acceptance commands. There is no review round. Record the checks and their outputs. |
| **L1 — one-pass light review (default)** | It is an ordinary implementation and does not meet an L0 or L2 trigger. | One independent reviewer in a clean context makes one pass. Triage findings: repair P1/P2 findings and run a targeted re-review; record P3 as nonblocking without rework. |
| **L2 — complete review loop** | The change is destructive or irreversible; touches secrets, authentication, or payment; changes a shared contract, schema, or persistence format; affects concurrency or races; or needs independent follow-up for a P1 found during L1 triage. | Use the full review-and-repair loop below. Use the strongest available independent-review shape and keep every re-review targeted. |

L0 is acceptance, not a reviewer verdict. The implementer never supplies an
independent review of its own work; this rule is unchanged at every tier. If a
mechanically decidable change reveals a semantic risk, move it to L1 or L2.

Mechanical surfaces do not belong in a review round. Deployment checks,
environment state, and fingerprint comparisons belong in an acceptance script;
the reviewer receives the script output plus the semantic surface that still
needs judgment. This keeps expensive reasoning on behavior and risk instead of
spending it on repeatable checks.

## Reviewer independence: a graceful spectrum

Independence means not sharing the implementer's context and blind spots. Start
with **a clean-context independent session**: a new session that has not seen
the implementation process, rationale, or prior discussion, and receives only
the delivery, the brief, the relevant specification, and the exact review
question. This is the lower bound, the default for Claude-only users, and a
first-class review path.

### Advanced options

When available, strengthen the default in this order:

1. **Same provider, different model or reasoning tier.** This is the middle of
   the spectrum.
2. **Different provider.** This is the strongest shape: independently built
   systems are less likely to share the same blind spots.

These are upgrades, not prerequisites. If they are unavailable, the
clean-context default still meets the independence floor. Provider access
changes the degree of independence, not whether independent review is required.

The implementer must not review its own delivery, even when no other reviewer
is convenient and even in L0. Writing code fills the implementer's context with
the reasons the change seemed correct; that is precisely the context an
independent review must avoid. Repeated familiar rereads can preserve the same
blind spot, while an independent reviewer can expose it. The value is a
non-shared viewpoint, not an assumption that one reviewer is smarter.

For L1, the clean session performs one complete pass. For L2, choose the
strongest available shape for the risk, then apply the same PASS, finding,
repair, and cap rules below. Do not turn provider availability into a reason to
skip independence.

## The review-and-repair loop

The reviewer receives the delivery and specification, checks semantic behavior,
and reports a verdict with findings. A FAIL requires a reproducible finding at
P2 or above; a P3 is explicitly **nonblocking**. On FAIL, send the original
implementer a repair brief containing the finding and the smallest relevant
context. After the repair, the next review is targeted: the brief contains only
the repair diff and that finding (plus the declared closure question when the
finding is a class), never a reopened full review.

R1 is the initial full review; each repair starts a targeted re-review, numbered
R2 and then R3.

Stop at the recommended **R3** review round. Reaching the cap is an escalation
to a human decision, not permission to keep adding patches. Across work orders
in the same work arc, a cumulative two consecutive review rounds with no new
P2-or-higher finding is the **review dry line**: do not open another generalized
review. A further review requires a targeted brief that says what it is looking
for and why the earlier rounds could not find it.

## Closing rules

For L1, L2, or any L0 change promoted into review, two rules decide whether the
review loop is closed:

1. **PASS is exact.** Accept only a reviewer PASS with `findings: []` against
   the exact final commit hash. If any repair commit lands after the latest
   PASS, regardless of author, start another targeted re-review. The author of
   even a one-line repair is the implementer for that commit, so self-report is
   not verification. The closing record must say:
   `PASS round reviewed HEAD = <hash>`.
2. **A repeated finding class is a strategy defect.** When the same class of
   finding appears for the second time, immediately use the strongest repair
   form rather than incrementally tightening a weak patch. For an assertion
   class, require whole-block byte-level equality. In the next round, enumerate
   the entire bypass surface for that class.

Before enumerating a finding class, state its closure condition: what must be
true for the class to be considered blocked? If that condition cannot be
stated, the class is not closable and the tier is wrong; re-tier the work
instead of enumerating indefinitely. A cheap, operational test for closure is
to find the cheapest bypass and ask whether the proposed defense stops it. If
it cannot stop the cheapest bypass, defenses against more expensive bypasses
are worthless: the wall has a hole.

A second FAIL on the same non-functional surface forces re-tiering, outside the
round cap. Ask whether the tier is still correct and whether the finding class
can be closed; do not write a third patch. The cap limits spend, not the cause
of failure.

Pure L0 closes without a review verdict: record the exact final HEAD, the diff
read, and the acceptance outputs. Otherwise, when the exact final HEAD has the
required PASS and no findings, record the tier, reviewer shape, round number,
reviewed hash, findings, targeted repairs, and acceptance outputs.
