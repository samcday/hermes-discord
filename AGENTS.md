# Working on hermes-discord

Read the relevant section before editing. Keep the README in the owner's voice.
Put operational detail in `docs/`, not in the README or a long skill.

| Task | Read |
| --- | --- |
| Setup, provider login, Discord access | [VM setup](docs/vm.md#first-run) |
| Replacement, storage, backups | [Operations](docs/vm.md#daily-use-and-replacement) |
| Privileges, networking, approvals | [Boundaries](docs/vm.md#boundaries) |
| Locate implementation and version pins | [Source map](docs/development.md#source-map) |
| Local tests and CI | [Checks](docs/development.md#checks) |
| Build a clean image without management access | [Base images](docs/development.md#base-images) |
| Preserve or promote self-modifications | [Runtime changes](docs/development.md#runtime-changes) |

Keep these rules:

- Keep `hermes-voice` VM, service, image, and state identifiers until an explicit migration.
- Keep the replaceable OS separate from the protected data disk.
- Keep credentials, live guest files, Tofu state, and private keys out of Git and CI artifacts.
- Do not restore stale OAuth snapshots or start concurrent authenticated clones.
- Run `just check` after code changes.
- Report image builds, boot tests, and live Discord tests separately.
- Use the configured landing workflow for publication. Passing tests is not merge approval.
