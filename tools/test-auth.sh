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

# --- S2: zero-credential argv assertions ------------------------------------
if grep -q -- '--no-refresh' "$ARGLOG/pi.argv" && ! grep -q -- '--credentials' "$ARGLOG/pi.argv"; then
    ok
else
    fail "[S2] pi argv: want --no-refresh present and --credentials absent; got: $(cat "$ARGLOG/pi.argv")"
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

echo "self-test: pass=$PASS fail=$FAIL"
[[ "$FAIL" == "0" ]] || exit 1
