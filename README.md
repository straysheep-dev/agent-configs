# agent-configs

![shellcheck workflow](https://github.com/straysheep-dev/agent-configs/actions/workflows/shellcheck.yml/badge.svg) ![yaml workflow](https://github.com/straysheep-dev/agent-configs/actions/workflows/yaml.yml/badge.svg) ![json workflow](https://github.com/straysheep-dev/agent-configs/actions/workflows/json.yml/badge.svg)

Harness-agnostic policy and bootstrap files for running coding agents against my codebase.

## Threat Model

Assume the harness's in-process controls can fail. Permission allow/deny lists, sandbox flags, seccomp/apparmor profiles; these are convenience guardrails maintained by fast-moving tooling, not an isolation boundary. They get bypassed by config bugs, race conditions, kernel/apparmor interaction issues, or scope creep the operator didn't notice.

The actual boundary is the instance where the harness lives, in many cases a VM. Packer-built, monitored, disposable image the agent runs inside of. If the harness's controls hold, that's a bonus. If they don't, the blast radius stops at the VM's network and filesystem. This repo's job is to configure the harness as an additional layer for defense in depth.

This also covers agent authentication. Assume your agent's authentication token can be stolen. Monitor and rotate; additionally the type of authentication that exists within the harness environment should also be limited (e.g. no browser sessions to your Claude web account).

## What's Here

| File / Directory | Purpose |
|-----------------|---------|
| `global-AGENTS.md` | Global policy for a trusted codebase, placed at `~/src/` |
| `untrusted-AGENTS.md` | Policy for reviewing untrusted codebases |
| `*-SESSION.md` / `*-TODO.md` | Placeholder handoff files; self-documenting, agent-maintained |
| `claude-settings.json` | Claude Code managed settings (sandbox required; `bootstrap.sh` applies the Ubuntu 24.04+ AppArmor/bwrap fix first) |
| `monitor.sh` | Operator's out-of-band egress check for the harness VM |
| `canary-test/` | Verifies whether the configured boundary actually holds |
| `outbox/` | Workflow handoff as format-patch series or scripting, for when the harness isn't available |

## How it Works

Policy cascades upward from the working directory. A single file at `~/src/AGENTS.md` (`~/src/CLAUDE.md` for Claude Code) means every repo under `~/src/` inherits it. Per-repo files contain **deltas only**, they extend or override, never duplicate.

## Bootstrap a New Harness VM

```bash
mkdir ~/src && cd ~/src
if [ ! -e ~/src/agent-configs ]; then
    git clone git@github.com:straysheep-dev/agent-configs.git
fi
cd agent-configs
bash ./bootstrap.sh [--trusted|--untrusted]
```

Defaults: `--trusted`.

`bootstrap.sh` installs `claude-settings.json` as `/etc/claude-code/managed-settings.json`, requiring the sandbox (`failIfUnavailable`). Before that, it checks `kernel.apparmor_restrict_unprivileged_userns` and, if AppArmor is blocking bubblewrap from creating user namespaces (the default on Ubuntu 24.04+), installs the allow profile from the [Claude Code sandboxing docs](https://code.claude.com/docs/en/sandboxing#ubuntu-24-04-and-later-allow-bubblewrap-to-create-user-namespaces) and reloads AppArmor.

## Related Repos

| Repo | Role |
|------|------|
| [`packer-configs`](https://github.com/straysheep-dev/packer-configs) | Packer templates (HCL2), the actual sandbox boundary; monitored, disposable |
| [`ansible-configs`](https://github.com/straysheep-dev/ansible-configs) | Ansible mono repo; consumed as submodule by packer-configs |
| [`ansible-role-template`](https://github.com/straysheep-dev/ansible-role-template) | Canonical scaffolding for new role repos |
| [`docker-configs`](https://github.com/straysheep-dev/docker-configs) | Molecule test containers per distro |
| [`linux-configs`](https://github.com/straysheep-dev/linux-configs) | Linux utilities useful in Ansible roles |
| [`windows-configs`](https://github.com/straysheep-dev/windows-configs) | Windows utilities useful in CI/CD and system configuration |

## License

[MIT](./LICENSE)

## Author Information

[straysheep-dev](https://github.com/straysheep-dev/)

Credit to the following sources for the ideas put into motion here:

- [BHIS: AI Security Ops](https://aisecurityops.transistor.fm/)
- [Anthropic Agent Harness Design](https://www.anthropic.com/engineering/harness-design-long-running-apps)
- [Daniel Miessler](https://danielmiessler.com/blog/)

> [!NOTE]
> **AI-assisted Authorship**
>
> This project adheres to the [Linux Kernel developer guidance on using AI coding assistants](https://docs.kernel.org/process/coding-assistants.html).
>
> Assisted-by: Claude:claude-fable-5
>
> Assisted-by: Claude:claude-opus-4-8
>
> Assisted-by: Claude:claude-sonnet-4-6, claude-sonnet-5
