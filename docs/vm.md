# VM setup and operations

The project is `hermes-discord`. Existing VM, service, image, and host-state names
remain `hermes-voice` to preserve the working installation.

## First run

Host tools: Linux/KVM, mkosi 26, OpenTofu 1.10+, libvirt, QEMU, OVMF, passt,
OpenSSH, `just`, Zenity, and GNOME Console (`kgx`). Libvirt must support
`qemu:///session`. QEMU must include `qemu-img`. Builds run without root on the
tested Fedora Silverblue host.

```sh
just build
just init
just storage       # review/create durable storage once
just plan
just up            # review/create the VM; allow a few seconds for first boot
just ssh true      # confirms the management connection is ready
just bootstrap     # install pinned Hermes and voice dependencies inside the guest
just discord       # one masked GNOME form: bot token + your numeric Discord ID
just login         # GNOME Console: select a model and provider
just activate      # start the image-owned systemd service
```

Create a Discord bot with text access, Connect/Speak permissions, and Message
Content Intent. Copy your numeric user ID with Discord's Developer Mode.
Supply the token only in the dialog, not a shell command or chat message.
Join your voice channel. Run `/voice join` from a dedicated text channel.
Transcripts and replies also appear there. Run `/voice leave` to disconnect.

`just login` opens Hermes' model and provider selection. ChatGPT uses a
browser-approved login, not a pasted password or API key. Other providers use
their own login methods. Supply credentials only through their private prompts.
Transcription uses local Whisper. Speech uses Edge TTS, a remote Microsoft
service separate from the model provider.

`just discord` sends credentials through SSH stdin. It does not put them in
command arguments, images, Tofu state, or this repository. Cancel leaves the guest
unchanged. The helper updates `.env` as `hermes` and preserves unrelated
configuration. It clears alternative role, channel, and global grants.
It does not revoke approved pairing entries or start the service.

## Daily use and replacement

```sh
just logs
just ssh                           # root management shell, not the agent's shell
just ssh systemctl status hermes-voice --no-pager
just stop                          # graceful guest shutdown; no disk deletion
just start
just build --force                 # rebuild OS from the descriptors
just plan                          # review replacement of VM + OS disk only
just up
```

The OS disk name includes the image hash. Replacement stops the old VM before
removing its OS volume. The data disk's stable virtio serial is `hermes-state`.
`x-systemd.makefs` initializes it only when empty. Missing or unmountable state
fails boot instead of creating disposable replacement credentials.

Host state lives under `${XDG_STATE_HOME:-$HOME/.local/state}/hermes-voice/`.
This private directory holds SSH keys, host-key records, provider data, two Tofu
states, and VM disks. Preserve the storage state and disk together.
Multiple checkouts manage the same VM. Do not apply competing configurations
concurrently.

Storage has a separate Tofu root, `prevent_destroy`, and pool deletion disabled.
These guards are not backups. Removing resource declarations or deleting disk
files defeats them. Runtime destruction does not own the data volume.

Do not restore stale OAuth snapshots or boot concurrent authenticated clones.
Refresh tokens rotate. Back up the stopped data disk securely.
It contains credentials and conversations.
See [runtime changes](development.md#runtime-changes) before promoting
self-modifications or changing the pinned application version.

## Boundaries

The current boundaries are:

- `hermes` is UID/GID 10000, has no sudo, and runs the gateway and tools.
  `terminal.backend: local` means inside the guest.
- The service has no capabilities or privilege escalation, and uses a private
  `/tmp`. Writable application data stays under its persistent home.
  SELinux stays enforcing.
- No host home, project mounts, SSH agent, Docker socket, microphone, GPU, or
  host credentials are forwarded. Management uses a separate host-only SSH key.
- SSH listens through passt at `127.0.0.1:22222` only, with key-only root login.
  Local first-use host-key trust is separate for each VM UUID.
  Changed keys for that VM are rejected. This is not remote attestation.
- Outbound networking is unrestricted. Passt/NAT can expose host and local
  network services. Later restrictions must live outside the guest.
  An HTTP proxy alone cannot control Discord UDP voice.
- The agent can read its guest credentials and change its own code under its
  home. VM isolation does not prevent token theft or abuse.
- Initially only your Discord ID is allowed. Manual approval covers flagged
  commands, not every command. It is not an operating-system security boundary.
  API/webhook adapters and the optional dashboard are off.
- Discord voice waits for silence and pauses listening during speech.
  It cannot listen and speak at the same time.
