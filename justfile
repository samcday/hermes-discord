set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

default:
    @just --list

# Build the guest OS and pinned bootstrap. Never includes account secrets.
build *args:
    ./scripts/build {{args}}

# Download the pinned provider; state lives outside the checkout.
init:
    ./scripts/tofu storage init
    ./scripts/tofu init

# Create durable storage separately from the replaceable VM.
storage:
    ./scripts/tofu storage apply

plan:
    ./scripts/tofu plan

# Review the plan, then approve creation/replacement interactively.
up:
    ./scripts/tofu apply

# Graceful shutdown; preserves both disks and current OAuth state.
stop:
    virsh --connect qemu:///session shutdown hermes-voice

start:
    virsh --connect qemu:///session start hermes-voice

console:
    virsh --connect qemu:///session console hermes-voice

ssh *args:
    ./scripts/vm-ssh {{args}}

# Install the pinned agent and voice extras as the unprivileged guest user.
bootstrap:
    ./scripts/vm-ssh runuser -u hermes -- /usr/local/libexec/hermes-voice/bootstrap

# One masked GNOME form; sends its result privately over SSH.
discord:
    ./scripts/configure-discord

# Open Hermes' own provider/OAuth wizard in GNOME Console.
login:
    ./scripts/login

# Start only after both account setup steps are complete.
activate:
    ./scripts/activate

check:
    ./scripts/check

# Inspect the generic image offline. Does not boot or contact the live VM.
image-check:
    python3 tests/image-smoke.py

# Uses upstream's managed environment runner; downloads the STT model if needed.
audio-check:
    ./scripts/vm-ssh 'cd /var/lib/hermes/.hermes/hermes-agent && exec runuser -u hermes -- scripts/run-in-hermes-env python -' < tests/audio-smoke.py

logs:
    ./scripts/vm-ssh journalctl -u hermes-voice.service -n 80 --no-pager
