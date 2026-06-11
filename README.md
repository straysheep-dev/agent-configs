# agent-configs

Agent configuration files to document and bootstrap workflows based on my existing codebase.

## What's here

| File / Directory | Purpose |
|-----------------|---------|
| `CLAUDE.md` | Global policy file governing Claude Code behavior across the entire source tree |
| `SESSION.md` | Running session notes and summaries from agent work; updated by the agent at the end of each session |
| `TODO.md` | Tracked open items and build-time debt; state that belongs out of `CLAUDE.md` |
| `outbox/` | Session handoff: format-patch series + apply scripts for automation without agents |

### SESSION.md

The agent appends a short summary here at the end of every session: what changed, what was validated in-sandbox, and what still needs operator review. It acts as a breadcrumb trail across sessions so context isn't rebuilt from scratch each time. Clear or archive it periodically - it's a working document, not a permanent log.

### TODO.md

Open items, deferred work, and known build-time debt live here. Keeping state out of `CLAUDE.md` means the policy file stays lean and every agent session isn't burning context re-reading resolved or stale items. The agent checks `TODO.md` at the start of each session to see whether the current task overlaps anything tracked.

### outbox Scripts

The idea here is use agents to solve problems, and turn the solutions into repeatable steps and code that the agent no longer has to invent. In the event the harness breaks, or goes away in the future, all of the existing scaffolding remains.

## How it works

[Claude Code](https://docs.anthropic.com/en/docs/claude-code) cascades `CLAUDE.md` files upward from the working directory. Placing a single file at `~/src/CLAUDE.md` means every repo under `~/src/` inherits these rules automatically.

Per-repo `CLAUDE.md` files contain **deltas only** - they extend or override specific rules for that repo without duplicating global policy. Each one opens with a comment flagging its relationship to this file:

```html
<!-- Extends ~/src/CLAUDE.md. Designed to work with the global policy but functional standalone. -->
```

Patterns, reusable task snippets, and role-specific documentation live in `docs/patterns/` inside the relevant downstream repo (e.g. `ansible-configs/docs/patterns/`), not here. This keeps context scoped to where it's actually used and avoids unnecessary token cost in unrelated sessions.

## Bootstrap a new harness VM

Clone this repo alongside your other source repos and symlink or copy the policy file into place:

```bash
cd ~/src
git clone git@github.com:<you>/agent-configs.git

# Option A - symlink (edits stay in the repo)
ln -s ~/src/agent-configs/CLAUDE.md ~/src/CLAUDE.md

# Option B - copy (if the harness environment restricts symlinks)
cp ~/src/agent-configs/CLAUDE.md ~/src/CLAUDE.md
```

`SESSION.md` and `TODO.md` are placeholders in this repo. On a fresh harness, symlink or copy them the same way so the agent always finds them at `~/src/SESSION.md` and `~/src/TODO.md`.

If you use Option B, add a provisioning step to re-copy on changes so deployed files don't drift from the repo.

### Claude Code settings.json

<https://code.claude.com/docs/en/settings>

The runtime configuration file for Claude Code - controls permissions (`allow`/`deny`/`ask`), model, effort level, env vars, and hooks. Distinct from `CLAUDE.md`: if `CLAUDE.md` is what the agent *reads*, `settings.json` is what shapes how the *harness runs*.

**Scope hierarchy (first match wins for most keys)**

| Scope | Path | Shared? |
|-------|------|---------|
| **Managed** | `/etc/claude-code/managed-settings.json` (Linux/WSL) | All users; cannot be overridden |
| **User** | `~/.claude/settings.json` | You, across all projects |
| **Project** | `.claude/settings.json` in repo root | All collaborators; committed to git |
| **Local** | `.claude/settings.local.json` in repo root | You only; gitignored |

Priority: `Managed > CLI args > Local > Project > User`

**Exception - permissions**: permission rules *merge* across scopes rather than override. A `deny` in user settings survives even if a project adds an `allow`. Deny is always evaluated first.

**For this setup**: `~/.claude/settings.json` on the harness VM. Applies across all repos under `~/src/` without being committed anywhere.

**Where it does not go**

- Not in `~/src/` - that's `CLAUDE.md` territory.
- Not committed to any repo without deliberate intent. A project-level `.claude/settings.json` overrides user settings for non-permission keys and stacks permission rules - a repo that gains one accidentally can silently widen what the agent can do.
- Not confused with `~/.claude.json` - that file holds OAuth sessions, MCP configs, and per-project trust state. Different file, same directory.

**Key gotchas**

**Environment variables beat `settings.json`** for some keys. `effortLevel: "high"` is ignored if `CLAUDE_CODE_EFFORT_LEVEL` is set in the shell environment. Check `~/.bashrc`, `~/.zshrc`, and `/etc/environment` on the harness VM after bootstrap.

**`model` does not hot-reload.** Most keys reload on file save mid-session. `model` is read once at session start - change it with `/model` or restart.

**`allowManagedPermissionRulesOnly`** locks the permissions block so only rules in `managed-settings.json` apply - user and project `allow`/`ask`/`deny` rules are ignored entirely. It only takes effect in managed scope (`/etc/claude-code/managed-settings.json`), so using it requires the bootstrap playbook to place a second file with root access alongside the user settings. It's a lock-down step for after your allowlist is stable, not a starting point. For a single-operator harness, the deny rules in `~/.claude/settings.json` plus the CLAUDE.md prohibition on the agent touching settings files covers the same threat.

### Ansible provisioning

TODO

## Related repos

| Repo | Role |
|------|------|
| `packer-configs` | Packer templates (HCL2); primary mono repo root |
| `ansible-configs` | Ansible mono repo; consumed as submodule by packer-configs |
| `ansible-role-template` | Canonical scaffolding for new role repos |
| `docker-configs` | Molecule test containers per distro |
| `linux-configs` | Linux utilities that often can be useful in Ansible roles |

## License

[MIT](./LICENSE)

## Author Information

[straysheep-dev](https://github.com/straysheep-dev/)

> [!NOTE]
> **AI-assisted Authorship**
>
> The following models and tools were used for drafts, examples, or research:
> - [Claude (`claude-sonnet-4.6`, `claude-opus-4.8`, `claude-fable-5`) via web and Claude Code](https://claude.com/product/overview)
