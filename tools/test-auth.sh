#!/usr/bin/env bash
# Self-test for tools/orca-auth.
#
# Every scenario runs against mock seat CLIs injected via PATH and fixture
# files injected via flags; it never touches the real machine's login state.
#
# Covers:
#   - all-green: 4 simple seats OK + pi[provider] OK + grok DEGRADED, exit 0
#   - zero-credential assertions: pi probe argv carries --no-refresh and never
#     --credentials; a sentinel value in an OK seat's raw output never reaches
#     --json output
#   - ATTN paths: rc!=0, logged-in shape drift, probe timeout
#   - MISSING (informational, exit stays 0 when the rest are green)
#   - grok tiers: file present / absent / empty
#   - --roles: seat filtering, MISSING->ATTN escalation, unreadable -> 64
#   - pi provider resolution: settings fallback note, --pi-providers list

set -uo pipefail

AUTH="$(cd "$(dirname "$0")" && pwd)/orca-auth"
PY=$(command -v "${PYTHON3:-python3}")   # absolute: PATH is emptied during runs

PASS=0
FAIL=0
FIXROOT=""

cleanup() { [[ -n "$FIXROOT" && -d "$FIXROOT" ]] && rm -rf "$FIXROOT"; }
trap cleanup EXIT

fail() { FAIL=$((FAIL + 1)); echo "FAIL: $*" >&2; }
ok() { PASS=$((PASS + 1)); }

run_auth() {
    set +e
    RUN_OUT=$(PATH="$FIXBIN" "$PY" "$AUTH" "$@" 2>&1)
    RUN_EXIT=$?
    set -e
}

jget() { "$PY" -c "import json,sys; d=json.load(sys.stdin); print($1)"; }

assert_exit() {
    local want=$1 label=$2
    [[ "$RUN_EXIT" == "$want" ]] && ok || fail "[$label] exit: want=$want got=$RUN_EXIT; out: $RUN_OUT"
}

seat_status() {
    printf '%s' "$RUN_OUT" | jget "next((s['status'] for s in d['seats'] if s['seat']=='$1'), 'NOTFOUND')"
}

assert_seat() {
    local seat=$1 want=$2 label=$3
    local got; got=$(seat_status "$seat")
    [[ "$got" == "$want" ]] && ok || fail "[$label] seat $seat: want=$want got=$got; out: $RUN_OUT"
}

# --- fixtures ---------------------------------------------------------------

FIXROOT=$(mktemp -d)
FIXBIN="$FIXROOT/bin"
mkdir -p "$FIXBIN"
export ARGLOG="$FIXROOT/argv"
mkdir -p "$ARGLOG"

SENTINEL="MOCK-SECRET-TOKEN-MUST-NOT-EMIT"

mk_mock() {  # mk_mock <name> <body...>
    local name=$1; shift
    { echo '#!/bin/bash'
      echo 'PATH=/usr/bin:/bin'   # mocks run under the emptied PATH
      echo "echo \"\$@\" >> \"\$ARGLOG/$name.argv\""
      printf '%s\n' "$@"
    } > "$FIXBIN/$name"
    chmod +x "$FIXBIN/$name"
}

mock_all_green() {
    mk_mock claude "echo '{\"loggedIn\": true, \"sentinel\": \"$SENTINEL\"}'"
    mk_mock codex  "echo 'Logged in using ChatGPT'"
    mk_mock opencode "printf '┌ Credentials\n● Mock\n└ 2 credentials\n'"
    mk_mock cursor-agent "echo '✓ Logged in as mock@example.com'"
    mk_mock pi "echo '{\"status\":\"ready\",\"provider\":\"mockprov\"}'"
    mk_mock grok "echo 'Grok Build TUI'"
}

PISET="$FIXROOT/pi-settings.json"
echo '{"defaultProvider": "mockprov"}' > "$PISET"
GROKAUTH="$FIXROOT/grok-auth.json"
echo '{"mock": true}' > "$GROKAUTH"

STD_FLAGS=(--json --pi-settings "$PISET" --grok-auth-file "$GROKAUTH")

# --- S1: all green ----------------------------------------------------------
mock_all_green
run_auth "${STD_FLAGS[@]}"
assert_exit 0 S1
assert_seat claude OK S1
assert_seat codex OK S1
assert_seat opencode OK S1
assert_seat cursor OK S1
assert_seat "pi[mockprov]" OK S1
assert_seat grok DEGRADED S1

# --- S2: zero-credential argv assertions (all seats, not only pi) -----------
if grep -q -- '--no-refresh' "$ARGLOG/pi.argv"; then
    ok
else
    fail "[S2] pi argv lacks --no-refresh; got: $(cat "$ARGLOG/pi.argv")"
fi
if grep -l -- '--credentials' "$ARGLOG"/*.argv 2>/dev/null; then
    fail "[S2] --credentials found in argv logs: $(grep -l -- '--credentials' "$ARGLOG"/*.argv)"
else
    ok
fi

# --- S3: sentinel from an OK seat's raw output never reaches --json ---------
if printf '%s' "$RUN_OUT" | grep -q "$SENTINEL"; then
    fail "[S3] sentinel leaked into --json output"
else
    ok
fi

# --- S4: rc!=0 -> ATTN, exit 1 ----------------------------------------------
mk_mock codex "exit 1"
run_auth "${STD_FLAGS[@]}"
assert_exit 1 S4
assert_seat codex ATTN S4

# --- S5: logged-in shape drift -> ATTN --------------------------------------
mock_all_green
mk_mock claude "echo '{\"loggedIn\": false}'"
run_auth "${STD_FLAGS[@]}"
assert_exit 1 S5
assert_seat claude ATTN S5

# --- S6: probe timeout -> ATTN ----------------------------------------------
mock_all_green
mk_mock cursor-agent "sleep 3" "echo done"
run_auth "${STD_FLAGS[@]}" --timeout 1
assert_exit 1 S6
assert_seat cursor ATTN S6
printf '%s' "$RUN_OUT" | jget "next((s['detail'] for s in d['seats'] if s['seat']=='cursor'),'')" | grep -q "timed out" && ok || fail "[S6] detail lacks 'timed out'"

# --- S7: MISSING is informational (exit 0 when the rest are green) ----------
mock_all_green
rm "$FIXBIN/opencode"
run_auth "${STD_FLAGS[@]}"
assert_exit 0 S7
assert_seat opencode MISSING S7

# --- S8/S9: grok file absent / empty ----------------------------------------
mock_all_green
run_auth --json --pi-settings "$PISET" --grok-auth-file "$FIXROOT/nope.json"
assert_exit 1 S8
assert_seat grok ATTN S8
: > "$FIXROOT/empty.json"
run_auth --json --pi-settings "$PISET" --grok-auth-file "$FIXROOT/empty.json"
assert_exit 1 S9
assert_seat grok ATTN S9

# --- S10: --roles filters seats ---------------------------------------------
ROLES="$FIXROOT/roles.json"
echo '{"roles": [{"id": "r1", "command": "claude --model m"}]}' > "$ROLES"
run_auth "${STD_FLAGS[@]}" --roles "$ROLES"
assert_exit 0 S10
assert_seat claude OK S10
[[ "$(printf '%s' "$RUN_OUT" | jget "len(d['seats'])")" == "1" ]] && ok || fail "[S10] want exactly 1 seat; out: $RUN_OUT"

# --- S11: --roles escalates a required MISSING seat to ATTN -----------------
echo '{"roles": [{"id": "r1", "command": "grok --agent x"}]}' > "$ROLES"
rm "$FIXBIN/grok"
run_auth "${STD_FLAGS[@]}" --roles "$ROLES"
assert_exit 1 S11
assert_seat grok ATTN S11

# --- S12: unreadable roles -> usage error 64 --------------------------------
run_auth "${STD_FLAGS[@]}" --roles "$FIXROOT/no-such-roles.json"
assert_exit 64 S12

# --- S13: pi settings missing and no --pi-providers -> ATTN with note -------
mock_all_green
run_auth --json --pi-settings "$FIXROOT/no-settings.json" --grok-auth-file "$GROKAUTH"
assert_exit 1 S13
assert_seat pi ATTN S13

# --- S14: --pi-providers probes each listed provider ------------------------
run_auth "${STD_FLAGS[@]}" --pi-providers alpha,beta
assert_exit 0 S14
assert_seat "pi[alpha]" OK S14
assert_seat "pi[beta]" OK S14

# --- S15: ATTN-shape sentinel must be redacted (human and --json) -----------
mock_all_green
mk_mock claude "echo '{\"loggedIn\": false, \"token\": \"$SENTINEL\"}'"
run_auth "${STD_FLAGS[@]}"
assert_exit 1 S15
assert_seat claude ATTN S15
if printf '%s' "$RUN_OUT" | grep -q "$SENTINEL"; then
    fail "[S15] sentinel leaked into --json ATTN detail"
else
    ok
fi
run_auth --pi-settings "$PISET" --grok-auth-file "$GROKAUTH"   # human output
if printf '%s' "$RUN_OUT" | grep -q "$SENTINEL"; then
    fail "[S15] sentinel leaked into human ATTN detail"
else
    ok
fi

# --- S16: grok file content must never reach output (stat-only probe) -------
mock_all_green
GROKSENT="$FIXROOT/grok-sentinel.json"
printf '{"apiKey": "%s"}' "$SENTINEL" > "$GROKSENT"
run_auth --json --pi-settings "$PISET" --grok-auth-file "$GROKSENT"
assert_seat grok DEGRADED S16
if printf '%s' "$RUN_OUT" | grep -q "$SENTINEL"; then
    fail "[S16] grok credentials file content leaked into output"
else
    ok
fi

# --- S17: non-object legal JSON -> ATTN, run survives -----------------------
mock_all_green
mk_mock claude "echo '[]'"
run_auth "${STD_FLAGS[@]}"
assert_exit 1 S17
assert_seat claude ATTN S17
assert_seat codex OK S17
mock_all_green
mk_mock pi "echo 'null'"
run_auth "${STD_FLAGS[@]}"
assert_exit 1 S17b
assert_seat "pi[mockprov]" ATTN S17b

# --- S18: ATTN detail is the whitelisted fingerprint shape ------------------
mock_all_green
mk_mock claude "$PY -c \"print('word '*80)\""
run_auth "${STD_FLAGS[@]}"
assert_seat claude ATTN S18
DET=$(printf '%s' "$RUN_OUT" | jget "next(s['detail'] for s in d['seats'] if s['seat']=='claude')")
if printf '%s' "$DET" | grep -qE '^rc=0; output: [0-9]+B sha256:[0-9a-f]{8}'; then
    ok
else
    fail "[S18] detail not the fingerprint shape: $DET"
fi
if printf '%s' "$RUN_OUT" | grep -q 'word'; then
    fail "[S18] raw probe output forwarded into report"
else
    ok
fi

# --- S19: --pi-providers strips names and OVERRIDES (seat count locked) -----
mock_all_green
run_auth "${STD_FLAGS[@]}" --pi-providers ' alpha , beta '
assert_exit 0 S19
assert_seat "pi[alpha]" OK S19
assert_seat "pi[beta]" OK S19
PIN=$(printf '%s' "$RUN_OUT" | jget "len([s for s in d['seats'] if s['seat'].startswith('pi')])")
[[ "$PIN" == "2" ]] && ok || fail "[S19] pi seat count: want 2 got $PIN (override, not union)"

# --- S20-S26: zero-forwarding sentinels across adversarial shapes -----------
# Every shape that beat the (now removed) redaction layer across review
# rounds R2/R3. Under zero forwarding they must ALL stay out of the report;
# any regression back to forwarding raw output turns these red.
redact_case() {  # redact_case <label> <mock-printf-arg> <secret>
    local label=$1 shape=$2 secret=$3
    mock_all_green
    { echo '#!/bin/bash'
      echo 'PATH=/usr/bin:/bin'
      echo "printf '%b\n' '$shape'"
    } > "$FIXBIN/claude"
    chmod +x "$FIXBIN/claude"
    run_auth "${STD_FLAGS[@]}"
    assert_seat claude ATTN "$label"
    if printf '%s' "$RUN_OUT" | grep -qF "$secret"; then
        fail "[$label] secret '$secret' leaked into output"
    else
        ok
    fi
    local det
    det=$(printf '%s' "$RUN_OUT" | jget "next(s['detail'] for s in d['seats'] if s['seat']=='claude')")
    if printf '%s' "$det" | grep -qE '^rc=[0-9-]+; output: [0-9]+B sha256:[0-9a-f]{8}'; then
        ok
    else
        fail "[$label] detail not the fingerprint shape: $det"
    fi
}
redact_case S20  '{"loggedIn": false, "password": "sh0rt!pw"}' 'sh0rt!pw'      # JSON field rule
redact_case S20b 'token: bare!val1'                            'bare!val1'     # bare field rule
redact_case S21  'Bearer tok3n!val'                            'tok3n!val'     # bearer rule
redact_case S22  'opaque ABCDE/FGHIJ+KLMNO=PQRSTUVW here'      'ABCDE/FGHIJ+KLMNO=PQRSTUVW'  # opaque incl. base64 charset
redact_case S23  '{"to\x1b[31mken": "sp1it!val"}'             'sp1it!val'     # ANSI-split key (R2)
redact_case S24  'Authorization: "Bearer quo!ted1"'            'quo!ted1'      # quoted Authorization value (R3 sol-S6)
redact_case S25  '{"to\x1b[?25lken": "dec!csi1"}'              'dec!csi1'      # DEC private-mode CSI split (R3 sol-S7)
redact_case S25b '{"to\x1b[38:5:31mken": "col!csi1"}'          'col!csi1'      # colon-form SGR split (R3 sol-S7)
redact_case S26  'access_token: comp!nd1'                      'comp!nd1'      # compound bare field name (R3 sol-S8)

echo "self-test: pass=$PASS fail=$FAIL"
[[ "$FAIL" == "0" ]] || exit 1
