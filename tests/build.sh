#!/usr/bin/env bash
# Exercise the real wrapper with fake build tools; never touch a VM or real key.
set -euo pipefail
repo="$(cd -- "$(dirname -- "$0")/.." && pwd)"
temporary="$(mktemp -d "${DELTA_SCRATCH_DIR:-${TMPDIR:-/tmp}}/hermes-build-test.XXXXXXXX")"
trap 'rm -rf -- "$temporary"' EXIT
mkdir -p "$temporary/repo/scripts" "$temporary/bin"
cp "$repo/scripts/build" "$repo/scripts/common" "$temporary/repo/scripts/"
cat > "$temporary/bin/tool" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "${0##*/}" in
    ssh-keygen)
        [[ ${FORBID_KEYGEN:-0} == 0 ]] || exit 99
        if [[ $1 == -y ]]; then
            printf 'ssh-ed25519 FAKE_TEST_PUBLIC_KEY\n'
        else
            printf 'FAKE_TEST_KEY\n' > "${!#}"
        fi
        ;;
    mkosi)
        printf '%s:%s\n' "${0##*/}" "$(umask)" >> build-masks
        printf '%s\n' "$@" > mkosi-args
        ;;
    qemu-img)
        printf '%s:%s\n' "${0##*/}" "$(umask)" >> build-masks
        printf '%s\n' "$*" >> qemu-args
        ;;
esac
SH
chmod +x "$temporary/bin/tool"
for name in ssh-keygen mkosi qemu-img; do
    ln -s tool "$temporary/bin/$name"
done
(
    umask 077
    PATH="$temporary/bin:$PATH" XDG_STATE_HOME="$temporary/state" \
        bash "$temporary/repo/scripts/build"
)
expected=$'mkosi:0022\nqemu-img:0022\nqemu-img:0022'
[[ $(< "$temporary/repo/build-masks") == "$expected" ]]
state="$temporary/state/hermes-voice"
[[ $(stat -c %a "$state") == 700 ]]
[[ $(stat -c %a "$state/id_ed25519") == 600 ]]
[[ $(stat -c %a "$state/authorized_keys") == 600 ]]
grep -Fxq -- "--extra-tree=$state/authorized_keys:/root/.ssh/authorized_keys" \
    "$temporary/repo/mkosi-args"
printf 'PASS: private keys stay private; image tools receive umask 022\n'

# A public build must ignore existing keys and also work with no host state.
for state_home in "$temporary/state" "$temporary/no-state"; do
    : > "$temporary/repo/build-masks"
    : > "$temporary/repo/qemu-args"
    (
        umask 077
        PATH="$temporary/bin:$PATH" XDG_STATE_HOME="$state_home" FORBID_KEYGEN=1 \
            bash "$temporary/repo/scripts/build" --base-image --force
    )
    [[ $(< "$temporary/repo/build-masks") == "$expected" ]]
    grep -Fxq -- --force "$temporary/repo/mkosi-args"
    grep -Fxq -- --output-directory=mkosi.output/base "$temporary/repo/mkosi-args"
    grep -Fxq -- --output=hermes-discord-base "$temporary/repo/mkosi-args"
    grep -Fxq -- --cache-directory=mkosi.cache/base "$temporary/repo/mkosi-args"
    if grep -q -- --extra-tree "$temporary/repo/mkosi-args"; then
        printf 'Base image unexpectedly includes an extra tree\n' >&2
        exit 1
    fi
    grep -Fxq -- \
        'convert -f raw -O qcow2 mkosi.output/base/hermes-discord-base.raw mkosi.output/base/hermes-discord-base.qcow2' \
        "$temporary/repo/qemu-args"
    grep -Fxq -- 'resize -f qcow2 mkosi.output/base/hermes-discord-base.qcow2 20G' \
        "$temporary/repo/qemu-args"
done
[[ ! -e "$temporary/no-state" ]]

root="$temporary/root"
mkdir -p "$root/etc" "$root/usr/local/libexec/hermes-voice"
printf '#!/bin/sh\n' > "$root/usr/local/libexec/hermes-voice/agent"
BUILDROOT="$root" sh "$repo/mkosi.postinst"
[[ ! -e "$root/root/.ssh/authorized_keys" ]]
[[ $(stat -c %a "$root/usr/local/libexec/hermes-voice/agent") == 755 ]]
mkdir -p "$root/root/.ssh"
printf 'FAKE_TEST_PUBLIC_KEY\n' > "$root/root/.ssh/authorized_keys"
BUILDROOT="$root" sh "$repo/mkosi.postinst"
[[ $(stat -c %a "$root/root/.ssh") == 700 ]]
[[ $(stat -c %a "$root/root/.ssh/authorized_keys") == 600 ]]
printf 'PASS: base images use separate outputs/cache and never enroll a management key\n'
