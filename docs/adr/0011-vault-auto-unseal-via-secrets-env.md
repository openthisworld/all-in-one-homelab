# 11. Vault auto-unseal via .vault-secrets.env

Date: 2026-05-08

## Status

Accepted. Amends ADR-0006.

## Context

ADR-0006 chose **manual unseal** for Vault as "intentionally simple": after
every pod restart (cluster boot, Docker Desktop restart, kind-node restart) the
operator runs `kubectl exec -it -n vault vault-0 -- vault operator unseal`
twice and pastes 2 of 3 unseal keys by hand.

In practice this fires every time Docker Desktop is restarted on the Mac mini —
several two-minute interruptions per week against a single-user homelab where
the unseal keys already need to live somewhere persistent. The friction works
against the platform mission ("full local cycle, one command") stated in the
README.

ADR-0006 explicitly leaves the door open: *"Future: if manual unseal becomes
annoying, can add Transit auto-unseal (second Vault instance — academic
exercise) or file-based unseal sidecar."*

The repo already commits to a gitignored `.vault-secrets.env` that stores the
Vault root token, GitHub OAuth credentials, and Dex client secrets — read by
`scripts/vault-seed.sh` to repopulate Vault after `kind delete`. Extending the
same file to also hold the unseal keys keeps secret material in one place,
behind one defence-in-depth (gitignore + gitleaks pre-commit hook), on
FileVault-encrypted disk, single-user.

The competing options were:

1. **Transit auto-unseal** — a second Vault instance unseals the first. Solves
   the operator-prompt problem but doubles the Vault footprint (~512 MiB RSS
   combined) and creates a chicken-and-egg: who unseals the transit Vault. The
   production answer is a cloud KMS, which is not available here.
2. **File-based unseal sidecar** — a sidecar reads keys from a Secret/file and
   pipes them in. Same plaintext-on-disk surface as option 3, plus an
   in-cluster moving part to maintain. No real defence-in-depth gain.
3. **Plaintext keys in `.vault-secrets.env`, replayed by a script.** Simplest
   thing that solves the problem. Single-user trade-off accepted.

## Decision

Store the unseal keys (all three, despite the 2-of-3 threshold) and the root
token in `.vault-secrets.env`. Two new scripts and one Justfile change:

- **`scripts/vault-auto-unseal.sh`** — sources `.vault-secrets.env`, pipes
  `VAULT_UNSEAL_KEY_1/2/3` (whichever are set) one-by-one into
  `kubectl exec -i -n vault vault-0 -- vault operator unseal -` until
  `Sealed: false` or until keys are exhausted. Idempotent: no-op + exit 0 on
  already-unsealed Vault. Distinct exit codes for missing env file (2), no
  keys set (3), Vault uninitialized (4), unseal failed (5).
- **`scripts/vault-init-and-save.sh`** — runs `vault operator init -key-shares=3
  -key-threshold=2`, prints the keys + root token to stdout, then asks
  `Append to .vault-secrets.env? [y/N]`. On yes, appends a fenced **managed
  block**:
  ```
  # >>> vault-init-and-save (managed block, do not edit) >>>
  VAULT_UNSEAL_KEY_1=...
  VAULT_UNSEAL_KEY_2=...
  VAULT_UNSEAL_KEY_3=...
  VAULT_ROOT_TOKEN=...
  # <<< vault-init-and-save <<<
  ```
  The fence makes re-runs detectable. On a subsequent run with an existing
  managed block (typically after `kind delete` + recreate, where Vault is
  uninitialized again and the old keys are dead), the script prompts
  `Existing managed block found from previous Vault instance — replace? [y/N]`
  and replaces in place on yes. If Vault is already initialized, the script
  exits without touching the file: rekey is a separate procedure
  (`vault operator rekey`), not this script's concern.
- **`Justfile`** — `just vault-unseal` becomes the auto path. The previous
  interactive flow is renamed `just vault-unseal-manual` and remains as the
  no-`.vault-secrets.env`-needed fallback. New `just vault-init-and-save`
  wraps the init script. `just vault-init` (raw `vault operator init`, no
  save) is kept for the rare case where the operator wants the keys printed
  but not written.

The keys never enter the chat with Claude or any other agent: the scripts read
`.vault-secrets.env` in the user's shell. `.vault-secrets.env` stays under the
existing `Never read` rule in `CLAUDE.md`.

`.vault-secrets.env.example` is extended with documented `VAULT_UNSEAL_KEY_1/2/3`
slots.

## Consequences

- One-command restart after a Docker Desktop reboot: `just vault-unseal`. ✅
- Bootstrap stays scriptable: `just vault-init-and-save` does the initial init
  + save in one prompt, removing the manual copy/paste of three keys into a
  password manager. ✅
- The unseal keys and root token sit in plaintext on disk. Compromise of the
  Mac (unlocked, FileVault decrypted, malware with read access to the user's
  home dir) yields full Vault access. **Acceptable for single-user homelab; not
  for multi-tenant.** Mitigations layered: gitignored, gitleaks pre-commit
  hook, FileVault, no sync to cloud storage.
- ADR-0006's manual-unseal stance is amended, not overturned: manual unseal is
  preserved as `just vault-unseal-manual` for the case where
  `.vault-secrets.env` is missing or corrupted, and remains the recommended
  procedure if this homelab is ever adapted to a multi-user context.
- Storing all three keys (vs. the 2-of-3 minimum) makes the file
  self-sufficient even if one key is malformed, at no incremental security
  cost: anyone who can read two can already read three.
- Rotation procedure: `vault operator rekey` regenerates unseal keys; the
  output replaces the managed block. Re-run `vault-init-and-save` semantics do
  **not** cover rekey — they only cover fresh init after a `kind delete`.
- If `.vault-secrets.env` is lost without backup and Vault is sealed, recovery
  is impossible — same as today. Backup discipline (e.g., encrypted iCloud
  Notes copy) is unchanged by this ADR.
- This ADR does not change ESO, the secret path convention, the Vault storage
  backend, or the post-init flow (`vault-setup`, `vault-seed`,
  `vault-setup-oidc`). ADR-0006 stays accepted.
