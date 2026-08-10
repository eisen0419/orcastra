#!/usr/bin/env bash
# Self-test for tools/orca-doctor.
#
# Freshly authored for this repo from the doctor's documented behavior, not
# ported from any other test suite. Every scenario is built from fixture
# directories and path-flag injection; it never depends on the real machine's
# Orca state.
#
# Covers:
#   - three top-level states: no Orca installed / runtime fake-green / all green
#   - each check's OK/WARN/FAIL paths where applicable
#   - exit codes 0/1/2 and --json summary fields
#   - CLI attribution: app (OK), stray (FAIL), broken link (WARN), none (WARN)
#   - runtime: missing (WARN), unparseable (WARN), stale-socket fake-green (FAIL),
#     live socket (OK)
#   - data: valid (OK), corrupt JSON (FAIL), schema mismatch (FAIL), no file (WARN)
#   - versions: missing plist (SKIP), unparseable plist (WARN), OK+CLI missing (WARN)
#   - --path-env empty-segment skip + dedup

set -uo pipefail

DOCTOR="$(cd "$(dirname "$0")" && pwd)/orca-doctor"
PY=${PYTHON3:-python3}

PASS=0
FAIL=0
FIXROOT=""

cleanup() {
    [[ -n "${LISTEN_PID:-}" ]] && kill "$LISTEN_PID" 2>/dev/null
    [[ -n "$FIXROOT" && -d "$FIXROOT" ]] && rm -rf "$FIXROOT"
}
trap cleanup EXIT

fail() {
    FAIL=$((FAIL + 1))
    echo "FAIL: $*" >&2
}

ok() {
    PASS=$((PASS + 1))
}

# Run the doctor; capture combined output + exit code into RUN_OUT / RUN_EXIT.
# errexit is disabled around the run because WARN/FAIL legitimately return 1/2.
run_doctor() {
    set +e
    RUN_OUT=$("$PY" "$DOCTOR" "$@" 2>&1)
    RUN_EXIT=$?
    set -e
}

# Extract a python expression `e` against JSON on stdin. Usage: echo "$j" | jget "d['summary']['fail']"
jget() {
    "$PY" -c "import json,sys; d=json.load(sys.stdin); print($1)"
}

# Assert RUN_EXIT equals $1; $2 is the scenario label.
assert_exit() {
    local want=$1 label=$2
    if [[ "$RUN_EXIT" == "$want" ]]; then
        ok
    else
        fail "[$label] exit code: want=$want got=$RUN_EXIT; output: $RUN_OUT"
    fi
}

# Assert a named check (substring match) has status $2 in RUN_OUT (JSON mode).
assert_check_status() {
    local name_sub=$1 want=$2 label=$3
    local got
    got=$(printf '%s' "$RUN_OUT" | jget "next((c['status'] for c in d['checks'] if '$name_sub' in c['name']), 'NOTFOUND')")
    if [[ "$got" == "$want" ]]; then
        ok
    else
        fail "[$label] check '$name_sub' status: want=$want got=$got; output: $RUN_OUT"
    fi
}

assert_summary() {
    local field=$1 want=$2 label=$3
    local got
    got=$(printf '%s' "$RUN_OUT" | jget "d['summary']['$field']")
    if [[ "$got" == "$want" ]]; then
        ok
    else
        fail "[$label] summary.$field: want=$want got=$got; output: $RUN_OUT"
    fi
}

set -e  # fixture-building commands should fail loudly

FIXROOT=$(mktemp -d "${TMPDIR:-/tmp}/doctor-test.XXXXXX")
mkdir -p "$FIXROOT"

# --- shared fixture builders ------------------------------------------------

write_plist() {  # $1=path $2=version
    cat > "$1" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleShortVersionString</key>
    <string>$2</string>
</dict>
</plist>
EOF
}

# valid local profile index (activeProfileId hits a valid record; no cloud field)
write_profile_index() {  # $1=path
    cat > "$1" <<'EOF'
{"schemaVersion":1,"activeProfileId":"local-default","profiles":[
{"id":"local-default","name":"Personal","avatar":{"kind":"initials","initials":"P","color":"neutral"},"kind":"local","createdAt":1,"updatedAt":2,"lastOpenedAt":3}
]}
EOF
}

write_valid_data() {  # $1=path
    cat > "$1" <<'EOF'
{"repos":[{"id":"r1"}],"worktreeMeta":{"w1":{"path":"/x"},"w2":{"path":"/y","isArchived":true}}}
EOF
}

# A listening unix socket server that accepts and immediately closes. Leaves the
# socket file present so the doctor's connect() succeeds. Args: socket path.
start_listening_socket() {
    "$PY" - "$1" <<'PYEOF' &
import socket, sys
path = sys.argv[1]
try:
    import os
    if os.path.exists(path):
        os.unlink(path)
except OSError:
    pass
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(path)
s.listen(8)
while True:
    try:
        conn, _ = s.accept()
        conn.close()
    except Exception:
        break
PYEOF
    LISTEN_PID=$!
    # wait for the socket file to appear
    for _ in $(seq 1 50); do
        [[ -S "$1" ]] && break
        sleep 0.05
    done
}

# A stale unix socket: bound then closed, file left behind, connect() refuses.
make_stale_socket() {  # $1=path
    rm -f "$1"
    "$PY" - "$1" <<'PYEOF'
import socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(sys.argv[1])
s.close()
PYEOF
}

# ============================================================================
# Scenario A: no Orca installed (all landing points missing)
# ============================================================================
echo "## Scenario A: no Orca installed"
A="$FIXROOT/a"; mkdir -p "$A/data" "$A/bin"
run_doctor --app-plist "$A/nonexistent.plist" --data-dir "$A/data" \
           --app-cli "$A/nonexistent-cli" --path-env "$A/bin" --json
assert_exit 1 "A: no Orca (WARN, no FAIL)"
assert_check_status "app version" "SKIP" "A: versions SKIP (no plist)"
assert_check_status "CLI attribution" "WARN" "A: cli WARN (no candidate)"
assert_check_status "runtime handshake" "WARN" "A: runtime WARN (no file)"
assert_check_status "data integrity" "WARN" "A: data WARN (no index, no root file)"
assert_summary "fail" 0 "A: zero FAIL"
assert_summary "warn" 3 "A: three WARN (versions is SKIP)"
assert_summary "skip" 1 "A: one SKIP"

# ============================================================================
# Scenario B: runtime fake-green (runtime json present + stale socket) -> FAIL
# ============================================================================
echo "## Scenario B: runtime fake-green"
B="$FIXROOT/b"; mkdir -p "$B/data" "$B/bin"
write_plist "$B/Info.plist" "9.9.9"
# CLI reachable as app: bin/orca -> symlink to app-cli endpoint
printf '#!/bin/sh\necho orca\n' > "$B/appcli"; chmod +x "$B/appcli"
ln -s "$B/appcli" "$B/bin/orca"
make_stale_socket "$B/stale.sock"
cat > "$B/data/orca-runtime.json" <<EOF
{"runtimeId":"x","pid":1,"transports":[{"kind":"unix","endpoint":"$B/stale.sock"}],"authToken":"t","startedAt":1}
EOF
run_doctor --app-plist "$B/Info.plist" --data-dir "$B/data" \
           --app-cli "$B/appcli" --path-env "$B/bin" --json
assert_exit 2 "B: fake-green -> FAIL"
assert_check_status "runtime handshake" "FAIL" "B: runtime FAIL (stale socket)"
assert_check_status "app version" "OK" "B: versions OK"
assert_check_status "CLI attribution" "OK" "B: cli OK (app via symlink)"
assert_summary "fail" 1 "B: one FAIL"

# ============================================================================
# Scenario C: all green
# ============================================================================
echo "## Scenario C: all green"
C="$FIXROOT/c"; mkdir -p "$C/data/profiles/local-default" "$C/bin"
write_plist "$C/Info.plist" "9.9.9"
printf '#!/bin/sh\necho orca\n' > "$C/appcli"; chmod +x "$C/appcli"
ln -s "$C/appcli" "$C/bin/orca"
write_profile_index "$C/data/orca-profile-index.json"
write_valid_data "$C/data/profiles/local-default/orca-data.json"
# one rolling backup present
cp "$C/data/profiles/local-default/orca-data.json" \
   "$C/data/profiles/local-default/orca-data.json.bak.0"
start_listening_socket "$C/live.sock"
cat > "$C/data/orca-runtime.json" <<EOF
{"runtimeId":"x","pid":1,"transports":[{"kind":"unix","endpoint":"$C/live.sock"}],"authToken":"t","startedAt":1}
EOF
run_doctor --app-plist "$C/Info.plist" --data-dir "$C/data" \
           --app-cli "$C/appcli" --path-env "$C/bin" --json
assert_exit 0 "C: all green -> exit 0"
assert_check_status "app version" "OK" "C: versions OK"
assert_check_status "CLI attribution" "OK" "C: cli OK"
assert_check_status "runtime handshake" "OK" "C: runtime OK (live socket)"
assert_check_status "data integrity" "OK" "C: data OK"
assert_summary "ok" 4 "C: four OK"
assert_summary "fail" 0 "C: zero FAIL"
# stop the listener for this scenario so it doesn't linger across later runs
kill "$LISTEN_PID" 2>/dev/null || true
unset LISTEN_PID

# ============================================================================
# CLI attribution: stray shadow -> FAIL
# ============================================================================
echo "## CLI: stray shadow -> FAIL"
CS="$FIXROOT/cs"; mkdir -p "$CS/bin"
write_plist "$CS/Info.plist" "9.9.9"
printf '#!/bin/sh\necho real-orca\n' > "$CS/appcli"; chmod +x "$CS/appcli"
printf '#!/bin/sh\necho stray-orca\n' > "$CS/bin/orca"; chmod +x "$CS/bin/orca"
mkdir -p "$CS/data"
run_doctor --app-plist "$CS/Info.plist" --data-dir "$CS/data" \
           --app-cli "$CS/appcli" --path-env "$CS/bin" --json
assert_check_status "CLI attribution" "FAIL" "stray: first candidate != app-cli -> FAIL"

# ============================================================================
# CLI attribution: broken symlink -> WARN
# ============================================================================
echo "## CLI: broken symlink -> WARN"
CB="$FIXROOT/cb"; mkdir -p "$CB/bin"
write_plist "$CB/Info.plist" "9.9.9"
printf '#!/bin/sh\n' > "$CB/appcli"; chmod +x "$CB/appcli"
ln -s "$CB/does-not-exist" "$CB/bin/orca"
mkdir -p "$CB/data"
run_doctor --app-plist "$CB/Info.plist" --data-dir "$CB/data" \
           --app-cli "$CB/appcli" --path-env "$CB/bin" --json
assert_check_status "CLI attribution" "WARN" "broken-link: unresolvable -> WARN"

# ============================================================================
# CLI attribution: --path-env empty-segment skip + dedup
# ============================================================================
echo "## CLI: path-env empty-segment skip + dedup"
CD="$FIXROOT/cd"; mkdir -p "$CD/bin"
write_plist "$CD/Info.plist" "9.9.9"
printf '#!/bin/sh\n' > "$CD/appcli"; chmod +x "$CD/appcli"
ln -s "$CD/appcli" "$CD/bin/orca"
mkdir -p "$CD/data"
# leading/trailing empty segments + bin repeated 3x -> still exactly 1 candidate,
# resolved as app -> OK
run_doctor --app-plist "$CD/Info.plist" --data-dir "$CD/data" \
           --app-cli "$CD/appcli" --path-env ":$CD/bin::$CD/bin:$CD/bin:" --json
assert_check_status "CLI attribution" "OK" "dedup+empties: app OK"
# detail must mention "1 candidate(s)" (dedup held)
n=$(printf '%s' "$RUN_OUT" | jget "next((c['detail'] for c in d['checks'] if 'CLI' in c['name']), '')")
if printf '%s' "$n" | grep -q "1 candidate(s)"; then ok; else fail "dedup: expected 1 candidate(s) in detail: $n"; fi

# ============================================================================
# versions: unparseable plist -> WARN (version issues never FAIL per spec)
# ============================================================================
echo "## versions: unparseable plist -> WARN"
VU="$FIXROOT/vu"; mkdir -p "$VU/data" "$VU/bin"
printf 'this is not a plist\n' > "$VU/Info.plist"
printf '#!/bin/sh\n' > "$VU/appcli"; chmod +x "$VU/appcli"; ln -s "$VU/appcli" "$VU/bin/orca"
run_doctor --app-plist "$VU/Info.plist" --data-dir "$VU/data" \
           --app-cli "$VU/appcli" --path-env "$VU/bin" --json
assert_check_status "app version" "WARN" "unparseable plist -> WARN (not FAIL)"

# ============================================================================
# versions: good plist but CLI not on PATH -> WARN
# ============================================================================
echo "## versions: good plist, no CLI on PATH -> WARN"
VN="$FIXROOT/vn"; mkdir -p "$VN/data" "$VN/emptybin"
write_plist "$VN/Info.plist" "9.9.9"
run_doctor --app-plist "$VN/Info.plist" --data-dir "$VN/data" \
           --app-cli "$VN/appcli" --path-env "$VN/emptybin" --json
assert_check_status "app version" "WARN" "good plist + no CLI -> WARN"
assert_check_status "CLI attribution" "WARN" "no candidate -> WARN"

# ============================================================================
# runtime: missing file -> WARN; unparseable -> WARN
# ============================================================================
echo "## runtime: missing + unparseable"
RM="$FIXROOT/rm"; mkdir -p "$RM/data" "$RM/bin"
write_plist "$RM/Info.plist" "9.9.9"
printf '#!/bin/sh\n' > "$RM/appcli"; chmod +x "$RM/appcli"; ln -s "$RM/appcli" "$RM/bin/orca"
run_doctor --app-plist "$RM/Info.plist" --data-dir "$RM/data" \
           --app-cli "$RM/appcli" --path-env "$RM/bin" --json
assert_check_status "runtime handshake" "WARN" "runtime missing -> WARN"
# unparseable
printf '{not json' > "$RM/data/orca-runtime.json"
run_doctor --app-plist "$RM/Info.plist" --data-dir "$RM/data" \
           --app-cli "$RM/appcli" --path-env "$RM/bin" --json
assert_check_status "runtime handshake" "WARN" "runtime unparseable -> WARN"

# ============================================================================
# data: corrupt JSON -> FAIL (with backup count in detail)
# ============================================================================
echo "## data: corrupt JSON -> FAIL"
DC="$FIXROOT/dc"; mkdir -p "$DC/data/profiles/local-default"
write_plist "$DC/Info.plist" "9.9.9"
printf '#!/bin/sh\n' > "$DC/appcli"; chmod +x "$DC/appcli"; mkdir -p "$DC/bin"; ln -s "$DC/appcli" "$DC/bin/orca"
write_profile_index "$DC/data/orca-profile-index.json"
printf '{not valid json' > "$DC/data/profiles/local-default/orca-data.json"
cp "$DC/data/profiles/local-default/orca-data.json" \
   "$DC/data/profiles/local-default/orca-data.json.bak.0"
run_doctor --app-plist "$DC/Info.plist" --data-dir "$DC/data" \
           --app-cli "$DC/appcli" --path-env "$DC/bin" --json
assert_check_status "data integrity" "FAIL" "corrupt data -> FAIL"
detail=$(printf '%s' "$RUN_OUT" | jget "next((c['detail'] for c in d['checks'] if 'data' in c['name']), '')")
if printf '%s' "$detail" | grep -q "1 .bak backup(s)"; then ok; else fail "corrupt data: detail must mention backup count: $detail"; fi

# ============================================================================
# data: schema mismatch -> FAIL
# ============================================================================
echo "## data: schema mismatch -> FAIL"
DS="$FIXROOT/ds"; mkdir -p "$DS/data/profiles/local-default" "$DS/bin"
write_plist "$DS/Info.plist" "9.9.9"
printf '#!/bin/sh\n' > "$DS/appcli"; chmod +x "$DS/appcli"; ln -s "$DS/appcli" "$DS/bin/orca"
write_profile_index "$DS/data/orca-profile-index.json"
printf '{"repos":"notarray","worktreeMeta":{}}' > "$DS/data/profiles/local-default/orca-data.json"
run_doctor --app-plist "$DS/Info.plist" --data-dir "$DS/data" \
           --app-cli "$DS/appcli" --path-env "$DS/bin" --json
assert_check_status "data integrity" "FAIL" "schema mismatch -> FAIL"

# ============================================================================
# data: active profile has no data file -> WARN
# ============================================================================
echo "## data: no data file -> WARN"
DN="$FIXROOT/dn"; mkdir -p "$DN/data/profiles/local-default" "$DN/bin"
write_plist "$DN/Info.plist" "9.9.9"
printf '#!/bin/sh\n' > "$DN/appcli"; chmod +x "$DN/appcli"; ln -s "$DN/appcli" "$DN/bin/orca"
write_profile_index "$DN/data/orca-profile-index.json"
# intentionally do NOT create profiles/local-default/orca-data.json
run_doctor --app-plist "$DN/Info.plist" --data-dir "$DN/data" \
           --app-cli "$DN/appcli" --path-env "$DN/bin" --json
assert_check_status "data integrity" "WARN" "no data file -> WARN"

# ============================================================================
# data: activeProfileId does not match a valid record -> WARN (no fallback)
# ============================================================================
echo "## data: activeProfileId mismatch -> WARN (no fallback)"
DA="$FIXROOT/da"; mkdir -p "$DA/data/profiles/local-default" "$DA/bin"
write_plist "$DA/Info.plist" "9.9.9"
printf '#!/bin/sh\n' > "$DA/appcli"; chmod +x "$DA/appcli"; ln -s "$DA/appcli" "$DA/bin/orca"
cat > "$DA/data/orca-profile-index.json" <<'EOF'
{"schemaVersion":1,"activeProfileId":"ghost","profiles":[
{"id":"local-default","name":"Personal","avatar":{"kind":"initials","initials":"P","color":"neutral"},"kind":"local","createdAt":1,"updatedAt":2,"lastOpenedAt":3}
]}
EOF
run_doctor --app-plist "$DA/Info.plist" --data-dir "$DA/data" \
           --app-cli "$DA/appcli" --path-env "$DA/bin" --json
assert_check_status "data integrity" "WARN" "activeProfileId mismatch -> WARN (no fallback guess)"

# ============================================================================
# usage error -> exit 64
# ============================================================================
echo "## usage error -> exit 64"
run_doctor --no-such-flag
assert_exit 64 "usage error -> 64"

# ============================================================================
# report
# ============================================================================
echo
echo "----------------------------------------"
echo "self-test: pass=$PASS fail=$FAIL"
if [[ "$FAIL" -ne 0 ]]; then
    exit 1
fi
exit 0
