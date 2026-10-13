# Development

Hermes runs in Discord with text, voice, and tools inside a Linux virtual machine
(VM). The operating system is replaceable. A separate disk holds the agent's code,
configuration, credentials, models, and memories.

## Source map

| Change | Source |
| --- | --- |
| Fedora 44, packages, boot, disk layout | [`mkosi.conf`](../mkosi.conf), [`mkosi.repart/`](../mkosi.repart/) |
| Guest user, network, SSH, service, initial configuration | [`mkosi.extra/`](../mkosi.extra/) |
| Pinned Hermes installer and voice extras | [`bootstrap`](../mkosi.extra/usr/local/libexec/hermes-voice/bootstrap) |
| Protected pool and 16 GiB data disk | [`infra/storage/`](../infra/storage/) |
| 4 vCPU / 4 GiB VM and 20 GiB OS disk | [`infra/runtime/`](../infra/runtime/) |
| Build, lifecycle, credential entry points | [`justfile`](../justfile), [`scripts/`](../scripts/) |
| Noninteractive fixtures and audio probe | [`tests/`](../tests/) |

The installer targets Hermes v0.21.6, commit
`818c13be1dc4fd28987e1e881a9408224afd4535`, with a pinned installer checksum.
The libvirt provider version and checksums are pinned. Fedora package repositories
are not frozen. The image manifest records installed packages, not a guarantee
of identical bytes across builds.

Hermes installs into its persistent home, not the OS image. Replacing the OS
does not upgrade, reset, or roll back the installed agent. The initial application
version is a baseline, not a claim about a self-modified running instance.

## Checks

Run on the host:

```sh
just check
```

Required tools: Bash, Python 3, ShellCheck, OpenTofu, mkosi 26, and `just`.
The command downloads locked providers into temporary directories with state
backends disabled. It needs no libvirt connection, VM image, credentials, or
`just init`.

It covers Bash syntax, ShellCheck, build permissions, credential fixtures, HCL
format and schema, and mkosi configuration parsing. Credential fixtures cover
cancellation, injection, symlinks, failure atomicity, and secret-free output.

The [checks workflow](../.github/workflows/check.yml) runs the same command on
pull requests, pushes to `main`, and manual runs. Passing these checks does not
prove that the image boots or Discord voice works.

`just audio-check` runs inside the guest. It tests Opus, real Edge synthesis,
and local Whisper transcription with a fixed public sentence. It needs network
access and model downloads, but no account key. It does not test Discord transport,
model inference, or billing.

`hermes doctor` reports npm advisories in unused bundled browser, web, and TUI
dependencies in the pinned release. Disabling those surfaces does not fix them.
Do not expose a dashboard or enable browser tooling without revisiting that finding.

## Base images

Build a clean OS image without a management key:

```sh
just build --base-image
just image-check
```

This uses `mkosi.output/base/` and a separate cache. It does not read or create
host management keys. Normal `just build` still creates the host-enrolled image
that OpenTofu uses.

`just image-check` needs `qemu-img`, `sfdisk`, and `debugfs`. It inspects the image
without root, mounts, or guest execution. It covers disk layout, permissions,
locked root access, and the absence of expected identity files. It is not a boot test.

The [image workflow](../.github/workflows/image.yml) runs on image-related pull
requests and manual runs. It uses a pinned Fedora container on a disposable
GitHub-hosted runner. The container needs privileges for mkosi's mounts and file
labels. It does not use the live VM or its storage.

The job uploads the compressed qcow2 image, package manifest, and checksums.
Artifacts expire after one day. It does not upload the sparse raw disk, caches,
keys, or Tofu state. It does not deploy or boot the image.

A base image is not a snapshot of the live VM. It contains neither the persistent
agent home nor its credentials, conversations, or self-modifications. It also lacks
a management login. Do not substitute it for the enrolled image in `just up`.
Management enrollment for downloaded images is a separate, unfinished step.

## Runtime changes

The data disk preserves self-modifications across OS replacements. It is not a
backup, a source repository, or a portable release. Follow the
[backup rules](vm.md#daily-use-and-replacement) for credentials and conversations.

To preserve a useful change in future installations:

1. Extract only the relevant source or configuration change from the guest.
2. Remove credentials, account identifiers, logs, and conversations.
3. Review the change on the host.
4. Add a test and express the change in this repository or a pinned upstream revision.
5. Use the configured `/land` workflow for review and publication.
6. Build and test the resulting image before replacing the live OS.

If `/land` is not configured, stop before publication.
This is a proposed promotion process, not an installed Hermes-to-Delta connector.
Keep GitHub publication credentials outside the guest. Do not give the agent host
SSH access or a shared desktop folder to automate this process.

Review gates control the build baseline. They do not control changes that the
running agent can already make and execute. Enforcing review before every live
code change requires read-only application code and a separate trusted updater.
That is a different mode from the current self-modifying VM.

Upstream: [Hermes](https://github.com/NousResearch/hermes-agent),
[mkosi 26](https://github.com/systemd/mkosi/blob/v26/mkosi/resources/man/mkosi.1.md),
[libvirt provider 0.9.9](https://github.com/dmacvicar/terraform-provider-libvirt/tree/v0.9.9).
