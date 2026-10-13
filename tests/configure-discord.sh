#!/usr/bin/bash
# Noninteractive tests with fake credentials only. Never call real SSH or Zenity.
set +x
set +v
set +a
set -euo pipefail
export LC_ALL=C

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
guest_helper=$repo/mkosi.extra/usr/local/libexec/hermes-voice/configure-discord
# shellcheck disable=SC1090
source "$guest_helper"
workspace=$(mktemp -d "${DELTA_SCRATCH_DIR:-${TMPDIR:-/tmp}}/configure-discord-tests.XXXXXXXXXX")
trap 'rm -rf -- "$workspace"' EXIT
mkdir -- "$workspace/bin" "$workspace/host"
cp -- "$repo/scripts/configure-discord" "$workspace/host/configure-discord"
cp -- "$repo/tests/configure-discord/vm-ssh" "$workspace/host/vm-ssh"
cp -- "$repo/tests/configure-discord/zenity" "$workspace/bin/zenity"
cp -- "$repo/tests/configure-discord/mv" "$workspace/bin/mv"
chmod 0700 "$workspace/host/"* "$workspace/bin/"*
export PATH="$workspace/bin:$PATH"
export TEST_GUEST_HELPER=$guest_helper
fake_token=FAKE.discord-token_42
case_count=0

fail_test() {
    printf 'FAIL: %s (case %s)\n' "$1" "$case_count" >&2
    exit 1
}

new_case() {
    case_count=$((case_count + 1))
    case_dir=$workspace/case-$case_count
    mkdir -- "$case_dir" "$case_dir/home"
    export TEST_HOME=$case_dir/home TEST_EVENT_LOG=$case_dir/events
    export STUB_FORM=success STUB_UNREACHABLE=0 STUB_WRITE_FAIL=0 STUB_RENAME_FAIL=0
    : > "$TEST_EVENT_LOG"
}

no_secret_output() {
    local output
    output=$(< "$case_dir/stdout")
    [[ $output != *"$fake_token"* ]] || fail_test 'token on stdout'
    output=$(< "$case_dir/stderr")
    [[ $output != *"$fake_token"* ]] || fail_test 'token on stderr'
}

run_host() {
    local expected=$1 actual=0
    shift
    bash "$@" "$workspace/host/configure-discord" \
        > "$case_dir/stdout" 2> "$case_dir/stderr" || actual=$?
    [[ $actual == "$expected" ]] || fail_test "host status $actual, expected $expected"
    no_secret_output
}

expect_events() {
    local actual
    actual=$(< "$TEST_EVENT_LOG")
    [[ $actual == "$1" ]] || fail_test 'unexpected SSH/prompt ordering'
}

expect_no_temporary() {
    local -a files
    shopt -s nullglob
    files=("$TEST_HOME/.hermes/".env.tmp.*)
    [[ ${#files[@]} == 0 ]] || fail_test 'temporary credential file remains'
}

canonical_settings() {
    printf '%s\n' \
        "DISCORD_BOT_TOKEN=$fake_token" \
        'DISCORD_ALLOWED_USERS=123456789012345678' \
        'DISCORD_ALLOW_ALL_USERS=false' \
        'DISCORD_ALLOWED_ROLES=[]' \
        'DISCORD_ALLOWED_CHANNELS=[]' \
        'DISCORD_ALLOW_BOTS=none' \
        'GATEWAY_ALLOWED_USERS=[]' \
        'GATEWAY_ALLOW_ALL_USERS=false'
}

assert_permissions() {
    [[ $(stat -c %a "$TEST_HOME") == 700 &&
       $(stat -c %a "$TEST_HOME/.hermes") == 700 &&
       $(stat -c %a "$TEST_HOME/.hermes/.env") == 600 ]] ||
        fail_test 'unsafe credential permissions'
    [[ $(stat -c %u:%g "$TEST_HOME/.hermes/.env") == "$(id -u):$(id -g)" &&
       $(stat -c %u:%g "$TEST_HOME/.hermes") == "$(id -u):$(id -g)" ]] ||
        fail_test 'incorrect credential ownership'
}

# Fresh guest: exactly one masked form, readiness check first, stdin-only write.
new_case
chmod 02755 "$TEST_HOME"
canonical_settings > "$case_dir/expected"
run_host 0
expect_events $'check\ndialog\nwrite'
cmp -s "$case_dir/expected" "$TEST_HOME/.hermes/.env" || fail_test 'incorrect settings'
assert_permissions
expect_no_temporary

# Preserve unrelated settings, comments, CRLF, shell-looking text, and quoted
# multiline values. Remove ALL old managed assignments, including duplicates,
# export/spacing variants, quoted keys, and multiline grants.
new_case
mkdir -- "$TEST_HOME/.hermes"
chmod 02755 "$TEST_HOME/.hermes"
cat > "$case_dir/unrelated" <<'ENV'
# Comments and unrelated platform policy are not ours.
MODEL="fake model # one"
OTHER='literal = # $value'
DISCORD_REQUIRE_MENTION=true
TELEGRAM_ALLOWED_USERS=999
MULTILINE="first
DISCORD_BOT_TOKEN=this-is-value-text
escaped \" quote
last"
SINGLE_MULTILINE='first
DISCORD_ALLOWED_ROLES=this-is-also-value-text
it\'s still unrelated'
DOTENV_ESCAPES="first \\"
DISCORD_ALLOWED_CHANNELS=still-value-text
last"
ENV
# Literal command substitution is intentional: the helper must not execute it.
# shellcheck disable=SC2016
printf 'UNEXECUTED=$(touch "%s/executed")\nCRLF=value\r\n' "$case_dir" >> "$case_dir/unrelated"
cp -- "$case_dir/unrelated" "$TEST_HOME/.hermes/.env"
cat >> "$TEST_HOME/.hermes/.env" <<'ENV'
 export DISCORD_BOT_TOKEN = 'old.fake.token'
'DISCORD_ALLOWED_USERS' = "123,
456"
DISCORD_ALLOW_ALL_USERS=true
DISCORD_ALLOWED_ROLES="12,
34"
DISCORD_ALLOWED_CHANNELS=*
DISCORD_ALLOW_BOTS=all
export GATEWAY_ALLOWED_USERS='*
another-user'
GATEWAY_ALLOW_ALL_USERS=yes
DISCORD_BOT_TOKEN=duplicate.fake.token
ENV
cp -- "$TEST_HOME/.hermes/.env" "$case_dir/original"
old_inode=$(stat -c %i "$TEST_HOME/.hermes/.env")
exec {original_fd}< "$TEST_HOME/.hermes/.env"
cat "$case_dir/unrelated" > "$case_dir/expected"
canonical_settings >> "$case_dir/expected"
run_host 0
cmp -s "$case_dir/expected" "$TEST_HOME/.hermes/.env" || fail_test 'unrelated settings changed'
[[ ! -e $case_dir/executed ]] || fail_test '.env was executed'
[[ $(stat -c %i "$TEST_HOME/.hermes/.env") != "$old_inode" ]] || fail_test 'update was not a rename'
cat <&"$original_fd" > "$case_dir/open-original"
exec {original_fd}<&-
cmp -s "$case_dir/original" "$case_dir/open-original" || fail_test 'old inode changed in place'
assert_permissions
expect_no_temporary
# Idempotent reconfiguration.
run_host 0
cmp -s "$case_dir/expected" "$TEST_HOME/.hermes/.env" || fail_test 'duplicate settings after reconfiguration'

# CR-only records must not silently discard unrelated settings.
new_case
mkdir -- "$TEST_HOME/.hermes"
printf 'DISCORD_BOT_TOKEN=old.fake.token\rUNRELATED=keep-me\r' > "$TEST_HOME/.hermes/.env"
cp -- "$TEST_HOME/.hermes/.env" "$case_dir/original"
run_host 2
expect_events $'check\ndialog\nwrite'
cmp -s "$case_dir/original" "$TEST_HOME/.hermes/.env" || fail_test 'CR-only settings were changed'
expect_no_temporary

# Cancellation and all malformed inputs leave existing guest settings untouched.
for form in cancel failure bad-id id-list negative-id zero-id leading-zero-id \
    overflow-id separator newline control nul empty missing-lf extra-lf oversized; do
    new_case
    mkdir -- "$TEST_HOME/.hermes"
    printf 'UNRELATED=original\n' > "$TEST_HOME/.hermes/.env"
    cp -- "$TEST_HOME/.hermes/.env" "$case_dir/original"
    export STUB_FORM=$form
    expected_status=2
    [[ $form != cancel ]] || expected_status=1
    run_host "$expected_status"
    expect_events $'check\ndialog'
    cmp -s "$case_dir/original" "$TEST_HOME/.hermes/.env" || fail_test 'invalid/cancelled form changed guest'
    expect_no_temporary
done

new_case
export STUB_UNREACHABLE=1
run_host 2
expect_events check
[[ ! -e $TEST_HOME/.hermes ]] || fail_test 'unreachable guest changed'

new_case
export STUB_WRITE_FAIL=1
run_host 2
expect_events $'check\ndialog\nwrite'
[[ ! -e $TEST_HOME/.hermes ]] || fail_test 'failed transport changed guest'

# Inherited Bash tracing and allexport must not leak credentials to output or
# the vm-ssh environment. The stub checks only our variable names, not values.
new_case
run_host 0 -a -x
expect_events $'check\ndialog\nwrite'

# Symlinks at the destination, home, .hermes, or ANY ancestor are rejected.
for destination in env dangling-env hermes-dir home ancestor; do
    new_case
    mkdir -- "$case_dir/target"
    printf 'UNRELATED=target\n' > "$case_dir/target/.env"
    cp -- "$case_dir/target/.env" "$case_dir/original"
    case $destination in
        env)
            mkdir -- "$TEST_HOME/.hermes"
            ln -s -- "$case_dir/target/.env" "$TEST_HOME/.hermes/.env"
            ;;
        dangling-env)
            mkdir -- "$TEST_HOME/.hermes"
            ln -s -- "$case_dir/missing" "$TEST_HOME/.hermes/.env"
            ;;
        hermes-dir) ln -s -- "$case_dir/target" "$TEST_HOME/.hermes" ;;
        home)
            rmdir -- "$TEST_HOME"
            ln -s -- "$case_dir/target" "$TEST_HOME"
            ;;
        ancestor)
            mkdir -- "$case_dir/target/durable"
            ln -s -- "$case_dir/target" "$case_dir/alias"
            export TEST_HOME=$case_dir/alias/durable
            ;;
    esac
    run_host 2
    cmp -s "$case_dir/original" "$case_dir/target/.env" || fail_test 'symlink target changed'
    [[ ! -e $case_dir/missing ]] || fail_test 'dangling symlink target created'
    expect_no_temporary
done

# Nonregular .env must never be read (a FIFO would hang) or overwritten.
for type in directory fifo; do
    new_case
    mkdir -- "$TEST_HOME/.hermes"
    if [[ $type == directory ]]; then
        mkdir -- "$TEST_HOME/.hermes/.env"
    else
        mkfifo -- "$TEST_HOME/.hermes/.env"
    fi
    run_host 2
    expect_no_temporary
done

# Failed parse/rename: atomicity, preservation, and no leftover secret temporary.
for failure in unterminated multiline-key nul rename; do
    new_case
    mkdir -- "$TEST_HOME/.hermes"
    case $failure in
        unterminated)
            printf 'UNRELATED="unfinished\nDISCORD_BOT_TOKEN=inside-value\n' > "$TEST_HOME/.hermes/.env"
            ;;
        multiline-key)
            printf "'unusual\nDISCORD_BOT_TOKEN=inside-key'=value\n" > "$TEST_HOME/.hermes/.env"
            ;;
        nul) printf 'UNRELATED=before\0after\n' > "$TEST_HOME/.hermes/.env" ;;
        rename)
            printf 'UNRELATED=original-without-newline' > "$TEST_HOME/.hermes/.env"
            export STUB_RENAME_FAIL=1
            ;;
    esac
    cp -- "$TEST_HOME/.hermes/.env" "$case_dir/original"
    run_host 2
    cmp -s "$case_dir/original" "$TEST_HOME/.hermes/.env" || fail_test 'failed transaction changed .env'
    expect_no_temporary
done

# Exercise the real guest validator independently of host validation. This
# internal fixture uses the caller UID, never the hardcoded live guest home.
run_guest_fixture() {
    # Dynamically scoped locals consumed by the sourced guest functions.
    # shellcheck disable=SC2034
    local +x discord_token discord_user
    local expected=$1 actual=0
    if discord_read_input; then
        discord_update_env "$TEST_HOME" > "$case_dir/stdout" 2> "$case_dir/stderr" || actual=2
    else
        actual=2
        : > "$case_dir/stdout"
        : > "$case_dir/stderr"
    fi
    [[ $actual == "$expected" ]] || fail_test "guest status $actual, expected $expected"
    no_secret_output
}

for payload in \
    "$fake_token|no" "$fake_token|1|2" "$fake_token|0" "$fake_token|01" \
    "$fake_token|18446744073709551616" "$fake_token|123"$'\r' \
    "$fake_token"$'\n'"INJECTED=1|123" "$fake_token"$'\t'"|123" \
    "$fake_token|123"$'\n'; do
    new_case
    printf '%s\n' "$payload" | run_guest_fixture 2
    [[ ! -e $TEST_HOME/.hermes ]] || fail_test 'invalid guest input changed filesystem'
done
new_case
printf '%s\0|123\n' "$fake_token" | run_guest_fixture 2
[[ ! -e $TEST_HOME/.hermes ]] || fail_test 'NUL input changed filesystem'
new_case
printf '%01100d|123\n' 0 | run_guest_fixture 2
[[ ! -e $TEST_HOME/.hermes ]] || fail_test 'oversized input changed filesystem'
new_case
printf '%s|123' "$fake_token" | run_guest_fixture 2
[[ ! -e $TEST_HOME/.hermes ]] || fail_test 'unterminated input changed filesystem'
new_case
printf '%s|18446744073709551615\n' "$fake_token" | run_guest_fixture 0
assert_permissions
expect_no_temporary

printf 'PASS: %s noninteractive Discord provisioning cases\n' "$case_count"
