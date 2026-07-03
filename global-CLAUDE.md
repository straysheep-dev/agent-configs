# CLAUDE.md - Infrastructure as Code

<!-- VERSION=0.5 -->
<!-- This file is policy, not state. Task state lives in TODO.md; session notes in SESSION.md. -->

<!--
MODEL GUIDANCE

CLAUDE.md cannot control model switching at runtime, the operator must do this.

Default: Sonnet (set in the settings.json on the harness VM or instance)
Override manually with --model if needed:
- Haiku: single-file edits, lint fixes, changelog fragments
- Sonnet: cross-file work, role scaffolding, multi-task sessions
- Opus: agent harness runs, novel problems, debugging loops
-->

This file governs Claude Code behavior across the entire source tree, using the `packer-configs` mono repo as the primary "root" path, where all submodules lead to. There are other mono repos next to this one, that are all downstream in some way, as submodules.

All files, including active `SESSION.md` and `TODO.md` files are intended to be published, and should be considered public. The entire codebase is public, and should not contain any secrets.

Per-repo `CLAUDE.md` files extend or override these rules where noted. Per-repo files contain **deltas only** - never copy this global file into a repo.

**Directory Map**

```
~/src/
├── CLAUDE.md                     # Global agent policy (this file, deployed from agent-configs repo)
├── SESSION.md                    # Summary gathered from any broad code or project review, edit only once per-session
├── TODO.md                       # Tracked open items and build-time debt (state, not policy)
├── outbox/                       # Session handoff: format-patch series + apply scripts for automation without agents
├── packer-configs/               # Packer templates (HCL2, JSON)
│   └── ansible-configs/          # Submodule of the mono repo
├── ansible-configs/              # Ansible mono repo
│   └── ./*                       # Mix: inline roles + roles as submodules + Ansible example files
├── ansible-role-template/        # Canonical template for new role repos
├── ansible-role-*/               # Individual role repos, added as submodules to ansible-configs
│   └── docker-configs/           # Submodule (Molecule containers + workflows)
│       └── <distro>/             # Submodule per container (Debian, Fedora, Kali, etc.) built from official base images + systemd support
└── docker-configs/               # Docker container mono repo
    └── <distro>/                 # Dockerfile per container (Debian, Fedora, Kali, etc.) configured with necessary tools + systemd
```

Always work on the "root" repo of any component when making changes. For example, when modifying an Ansible role that is its own repo, make changes directly to the `ansible-role-<role_name>` repo, and note the upstream submodule sync commands for the operator to reference (these are often documented in the mono repo README files). When adding a new role, follow the `ansible-role-template` structure exactly - do not invent a new layout.

## General Automation Guidance

You do not have access to the `gh` tool, or the ability to write back to GitHub. You're in an isolated sandbox that *can* stage changes and modify git, but in all cases the operator will extract the proposed changes after review and apply them manually. Your goal as the agent is to problem solve and draft the changes. All chores, cleanup items, and other tasks that can be built as code, should be, once they're identified - produce bash or python snippets the operator can run to automate the task out of the agent loop.

### Session Handoff (output contract)

Every session that produces changes ends with:

1. One commit (or small logical series) per touched repo, with conventional messages.
2. `git format-patch` output written to `~/src/outbox/<repo-name>-<topic>-<yyyymmdd>`.
3. An `apply.sh` in the same directory: the exact `git` (and submodule bump) commands for the operator, in dependency order.
4. A short summary appended to `SESSION.md`: what changed, what was validated in-sandbox, what still needs operator eyes.

Validation the agent can run itself (lint, `packer validate`, Molecule) is run **before** handoff. Never hand off unvalidated changes without flagging them as such.

## Ansible Conventions

- Create any new roles using the `ansible-role-template` repo as the base.
  - If you see any areas for improvement to `ansible-role-template` that also do not limit the template for general use, share them with the operator for input before making changes.
- Adhere to the [ansible-lint rules](https://docs.ansible.com/projects/lint/rules/) by default, and use `ansible-lint` to validate
- If the design of a role conflicts with `ansible-lint`, and there's truly no work-around possible after reviewing ways to achieve the goal with an existing module, one of the following options should be used:
  - Try to achieve it with the `command:` or `shell:` modules
  - Use tags like `molecule-notest` and `molecule-idempotence-notest` if there's no other way
  - Note this for the operator to review
- **No third-party Ansible modules**: built-in and collection modules only. If a gap exists, document it for review.
- If shell is unavoidable, add an inline comment describing why, citing the module documentation, and use `set -o pipefail` in multiline scripts.
- **No hardcoded secrets**: use `ansible-vault` encrypted vars or `vars_prompt`. Never suggest plaintext credentials in any file. In most cases, a dev vault can be used with a throw-away passphrase.
- `changed_when` and `failed_when` must be set on any `shell:` or `command:` task.
- `no_log: true` on any task whose parameters or registered output could contain secret material (vault vars, tokens, generated passwords).

### Hardening Roles (attack-driven, not benchmark-driven)

Hardening is scoped to controls we can demonstrate an attack against - not blanket benchmark coverage.

- One role per attack surface: `ansible-role-<action>-<surface>` (e.g. `configure-kernel`, `configure-sshd`, `manage-apt`).
- Each control in the role maps to a documented threat. The role README contains a **threat table**: control > attack it mitigates > evidence (MITRE ATT&CK technique ID, public PoC link, or a pentest note from the operator's research).
- `molecule/verify.yml` asserts the *control state itself* (sysctl value set, sshd flag present, pam options active) - one assert per control, so the role is its own compliance proof.
- A control with no demonstrable attack and no evidence entry does not belong in a hardening role. Propose it in the README under "Candidates" for operator review instead.
- CIS/STIG mappings are optional metadata in the threat table (an export view), never the organizing principle. Do not structure roles or tags around benchmark section numbers.
- Destructive or lockout-capable controls (firewall default-deny, sshd auth changes, sudoers rewrites) must ship with an escape-hatch variable documented in `defaults/main.yml` and called out in the README.

### Variables

- All role defaults live in `defaults/main.yml` with inline YAML comments describing each variable. Mirror these in the role's README. These comments are the documentation source.
- `vars/main.yml` is for internal constants only, never user-facing.
- Separate list shapes that differ structurally into distinct variables (e.g. `user_list`, `delete_user_list`, `expire_user_list`) to prevent accidental destructive operations from shape mismatches.
- Use the `default()` filter instead of the two-task `when: var is defined` / `when: var is not defined` patterns.

### Task files

- One focus per task file under `tasks/`.
- Consolidation, modularity, and concision are ideal goals.
    - Prefer scaffolding for tasks with variables driving the behavior out of `defaults/main.yml`
    - For example, one task block driven by user-defined variables with built-in defaults, that works for all OS's is better than 5 static task blocks covering multiple OS's.
- Include files are named for what they do: `create-users.yml`, `authorized-keys.yml` - not `main2.yml` or `misc.yml`.
- Tags must be consistent and documented in `meta/main.yml`.

### Ansible Lint

- All roles should use a standardized `.ansible-lint` file that comes with the `ansible-role-template` repo.
- If any changes are worth making per-role, note them for operator review before making them.

### Molecule

- Every role requires a `molecule/default/` scenario.
- `verify.yml` must contain at least one `ansible.builtin.assert` per observable side effect of the role (file created, service running, user exists, etc.).
- Platform matrix is defined in `molecule.yml` and must reference images built locally from the `docker-configs` submodules only.
- Images are not published to any registry. They are built and cached locally from the per-distro submodules inside `docker-configs` (e.g. `docker-configs/debian/`, `docker-configs/fedora/`).
- Do not reference Docker Hub, GHCR, or any external registry for Molecule platforms. Do not suggest `geerlingguy/*` or any third-party images as a substitute. If anything isn't working with an existing image, or a required image is missing, note this and draft suggested changes to the dockerfile for the operator to review.
- Kernel-level controls (sysctl, modules) cannot be fully verified in containers. Assert the configuration files/values in Molecule, and note in the README which controls require VM-based verification by the operator.

---

## Packer Conventions

- All templates created from scratch are HCL2.
- Review template structures and provide feedback or suggestions for operator review if anything can be consolidated or optimized.
- Some existing templates are in JSON for historical reference, they should also have an HCL template mirroring them.
- Do not use any unofficial, or third-party plugins. If you need to add plugins, note them for the operator to review and do not install them.
- `required_plugins` versions must be pinned.
- ISO checksums must be pinned. Never use `none` or a floating URL. The operator must confirm these are correct. Never modify these.
- Secrets passed as variables must have `sensitive = true`.
- `execute_command` shell scripts must begin with `set -o pipefail`.
- `ssh_private_key_file` over `ssh_password` wherever possible.
- `headless` must be an overridable variable (`var.headless`), defaulting to `true`, so `-var "headless=false"` enables interactive debugging.
- `qemuargs` block: only flags that Packer's native fields cannot handle (e.g. `["-cpu", "host"]`). Document each entry with an inline comment. Duplicate or conflicting flags are a real risk - check before adding.

### Build Targets

- Ubuntu and Rocky Linux *server* templates are the baselines.
- Desktop templates are built from server ISOs, using Ansible provisioning and specific packages or package groups.
- ansible-configs is consumed as a submodule inside packer-configs; do not duplicate role logic in Packer shell provisioners.

### Packer Lint

- Validate templates using `packer fmt -recurse .` and `packer validate`.

---

## Security Posture

- Treat every file in this repo as public. They will all be published.
- Secrets management:
  - Assume SOPS + age or a vault will be in use from the Ansible controller or orchestration node.
  - The existing `vault.example.txt` is meant for dev use, and is already published to the repo (meant to be replaced in production).
  - `pwfile` contains the string of `password123`, and unlocks the `vault.example.txt` file.
  - Never reference the dev vault or `pwfile` in anything intended for production paths; treat them as fixtures only.
- Sudoers entries
  - cloudinit will deploy the default `NOPASSWD: ALL` exception via packer (for use during the build process).
  - When writing roles to customize or harden the sudoers configuration, scope exceptions as narrowly as possible (no `NOPASSWD: ALL`).
- Always validate input when building tasks, wrapper scripts, or similar files that will be used or deployed by workflows.

Signature and integrity checking operations for tasks and workflows:

- Always build workflows to validate the key string, detached signatures, or at least the checksum, depending on what's available. Opt for signature checking like GPG or Cosign over hashes alone when possible, note when signatures are not available.
- Inspect key files without touching any keyring: `gpg --no-keyring --with-colons --with-fingerprint <file>`.
- Canonical reusable patterns live under `ansible-configs/docs/patterns/*`: extract fingerprints machine-readably, normalize, and `assert` every expected fingerprint from `defaults/main.yml` is present. Expected fingerprints are researched and validated values the operator provides or confirms - never trust a freshly downloaded key blindly. Reuse and update these patterns; do not reimplement them per role.

---

## CI / GHA

- `ansible-lint` runs with the `safety` profile. All violations must be resolved, not ignored, unless a `# noqa` comment includes a justification.
- `shellcheck` runs on all `.sh` files.
- `yamllint` runs on all `.yml` files.
- Molecule uses the `docker-configs` containers.
- Workflows follow the permissions-minimization pattern: `permissions: {}` at workflow level, minimum grants at job level.

---

## Before you start

0. If SESSION.md exists, review it to gather any previous summary or notes. If TODO.md exists, check whether the current task overlaps an open item.
1. Read the relevant `README.md` and `defaults/main.yml` before modifying any repo.
2. Do not infer project purpose or other details, if anything is unclear, ask questions for clarification and convey what's missing.
3. State your understanding of the task and any ambiguities before writing code. Ask rather than assume on destructive operations (delete, expire, overwrite).
4a. If the task would require writing non-trivial custom code to solve a problem that a well-known, purpose-built external tool or library is specifically designed for, flag it: name the candidate, explain why it's relevant, and stop. Do not research it further, do not wire it in, and do not proceed with implementation until the operator responds.
4b. Before creating any new file or role, check whether something in the local tree already addresses the concern or could be adapted. Prefer adapting existing work over adding new files.

## Definition of done

A change is complete when:

- `ansible-lint`, `yamllint`, and `shellcheck` pass (or `packer fmt -check` + `packer validate` for templates).
- Molecule converge + verify + idempotence pass for any touched role (or the gap is flagged in the handoff summary).
- `defaults/main.yml` comments and the README agree.
- Hardening roles: threat table updated for any added/changed control.
- Handoff artifacts exist based on the Session Handoff contract.

---

## Submodules

- **Edit code only in the standalone clone** of a repo (e.g. `~/src/ansible-role-<name>/`), never through a submodule path inside a parent repo.
- **Never run git submodule plumbing** (`init`, `update`, `sync`, `add`, pointer bumps). If a submodule needs any git operation, write the exact suggested commands into the handoff `apply.sh` and stop - the operator runs them.

---

## What not to do

- Do not suggest `ansible-galaxy install` or any third-party packer plugins, for anything.
- Do not create `group_vars/all` files that would override role defaults silently across unrelated plays.
- Do not add dependencies to `meta/main.yml` without sharing the suggestion and receiving operator confirmation first.
- Do not put task state or open items in this file - they go in `TODO.md`.
- Only edit `SESSION.md` once per-session, otherwise there's likely no effective benefit from prompt caching.

---

<!-- Open Items moved to ~/src/TODO.md  -->