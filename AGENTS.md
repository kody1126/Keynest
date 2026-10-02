# Keynest project rules

## Scope and data safety

This repository is the Keynest project only. Do not publish the parent tools workspace or unrelated projects.
Never read, commit, upload or use real vault contents, API credentials, biometric enrollment files, local app backups, `.data`, `.env`, `.keynest` or `.keynestlocal` files. Run checks with isolated temporary directories and fictitious credentials. Preserve the native/Web data separation and existing vault compatibility.

## GitHub synchronization

The maintainer has requested that future updates to this project be synchronized to https://github.com/kody1126/Keynest after verification. This is authorization to commit and push reviewed, task-related project changes; it is not an instruction to continuously upload the working directory.

For each completed update:

1. Review the diff and run the checks appropriate to the change. Keep `README.md` (Chinese) and `README.en.md` (English) consistent when user-facing behavior, security, build or installation instructions change.
2. Inspect staged paths and contents for credentials, private local data, generated build output and unrelated changes. Do not use force-add to bypass secret/build exclusions.
3. Commit the intended changes and push the current project branch to `origin`. Check remote state first; never force-push, overwrite others' changes, or silently resolve a conflicting remote history. Use `codex/` for new task branches when a branch is needed.
4. Verify the remote commit and relevant CI result. Report the commit/repository link. If authentication, network or CI fails, state that synchronization is incomplete rather than claiming success.

Respect a later instruction to keep an update local or not push. Do not install background watchers, cron jobs or hooks that automatically publish unreviewed files. Release assets are separate from source commits; publish a new release only when a version is intentionally prepared. Never overwrite an existing release asset without a clear versioning decision.

## Checks

- Native core: `cd macos && bash scripts/run-checks.sh`
- Native app model: `cd macos && bash scripts/run-app-checks.sh`
- Biometric file boundaries only: `cd macos && bash scripts/run-biometric-checks.sh --file-only`
- Legacy Web experiment: `npm test` (Node.js 22+)
- Release: build/package scripts documented in `macos/README.md`; generated output stays ignored.

Do not invoke interactive biometric enrollment or real provider APIs during automated tests. Do not describe the experimental app as independently audited, sandboxed, notarized, or absolutely secure. Preserve third-party licenses and brand-source records when updating icons.
