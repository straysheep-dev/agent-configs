#!/bin/bash

# SPDX-License-Identifier: MIT
# Assisted-by: Claude:claude-sonnet-5

# Bootstraps harness-agnostic policy files + Claude Code's runtime config onto a
# fresh VM. Run from ~/src/agent-configs. Needs sudo for the AppArmor bwrap fix,
# the Claude Code managed-settings install, and (in --untrusted mode) the
# analysis toolchain.

# Changelog:
# - 2026.07.05: First draft of bootstrap.sh
# - 2026.08.16: Add support for untrusted environments + utility installation
# - 2026.08.29: Pin python toolchain via uv, exit non-zero on failure
# - 2026.09.12: Add the Ubuntu 24.04+ AppArmor/bwrap userns fix
# - 2026.09.13: Load bwrap profile via apparmor_parser -r

set -euo pipefail

failed=0    # Set failure var
readonly SRC_DIR="${HOME}/src"
readonly REPO_DIR="${HOME}/src/agent-configs"

usage() {
    cat >&2 <<'EOF'
Usage: bootstrap.sh [--trusted|--untrusted]

  --trusted            global policy profile (default): your own repos
  --untrusted          tool-review profile + static-analysis toolchain
EOF
}

mode="trusted"

while [[ $# -gt 0 ]]; do
    case "${1}" in
        --trusted)   mode="trusted" ;;
        --untrusted) mode="untrusted" ;;
        -h|--help)   usage; exit 0 ;;
        *)
            printf "[!] Unknown flag '%s'\n" "${1}" >&2
            usage
            exit 1
            ;;
    esac
    shift
done
readonly mode

prefix="global"
[[ "${mode}" == "untrusted" ]] && prefix="untrusted"
readonly prefix

readonly POLICY_SRC="${prefix}-AGENTS.md"

# SESSION.md / TODO.md keep their names on every harness. Kept in both profiles.
readonly -a STATE_FILES=("SESSION.md" "TODO.md")

# Ensure ~/src exists; if we had to create it, we obviously weren't in it.
if [[ ! -d "${SRC_DIR}" ]]; then
    mkdir -p "${SRC_DIR}"
    printf "[!] %s did not exist, created it (we are not actually inside ~/src)\n" "${SRC_DIR}" >&2
    exit 1
fi

# Must be run from ~/src/agent-configs, else fail.
if [[ "$(pwd)" != "${REPO_DIR}" ]]; then
    printf "[!] must be run from %s\n" "${REPO_DIR}" >&2
    exit 1
fi

printf "[*] Bootstrapping: mode=%s\n" "${mode}"

# Copy a repo file to ~/src/<dst>, not symlink.
place_file() {
    local src="${1}" dst="${2}"
    local src_path="${REPO_DIR}/${src}"
    local dst_path="${SRC_DIR}/${dst}"

    if [[ ! -f "${src_path}" ]]; then
        printf "[!] source %s missing, skipping\n" "${src_path}" >&2
        failed=1
        return
    fi

    if [[ -e "${dst_path}" ]]; then
        printf "[*] %s exists, skipping\n" "${dst_path}"
        return
    fi

    install -m 0644 "${src_path}" "${dst_path}"
    printf "[*] Copied %s -> %s\n" "${src}" "${dst_path}"
}

place_file "${POLICY_SRC}" "CLAUDE.md"
for state_file in "${STATE_FILES[@]}"; do
    place_file "${prefix}-${state_file}" "${state_file}"
done

mkdir -p "${SRC_DIR}/outbox"
printf "[*] Ensured %s exists\n" "${SRC_DIR}/outbox"

# --- Claude Code runtime config -----------------------------------------------

readonly MANAGED_DIR="/etc/claude-code"
readonly MANAGED_PATH="${MANAGED_DIR}/managed-settings.json"
readonly BWRAP_PROFILE="/etc/apparmor.d/bwrap"

# Ubuntu 24.04+ ships an AppArmor policy that blocks bwrap from creating the
# user namespaces the sandbox needs. See:
# https://code.claude.com/docs/en/sandboxing#ubuntu-24-04-and-later-allow-bubblewrap-to-create-user-namespaces
allow_bwrap_userns() {
    local restricted
    restricted="$(sysctl -n kernel.apparmor_restrict_unprivileged_userns 2>/dev/null || true)"
    [[ "${restricted}" == "1" ]] || return 0

    sudo tee "${BWRAP_PROFILE}" > /dev/null <<'EOF'
abi <abi/4.0>,
include <tunables/global>

profile bwrap /usr/bin/bwrap flags=(unconfined) {
  userns,
  include if exists <local/bwrap>
}
EOF
    sudo apparmor_parser -r "${BWRAP_PROFILE}"
    printf "[*] Installed %s, loaded into the kernel via apparmor_parser (bwrap can now create user namespaces)\n" "${BWRAP_PROFILE}"
}

install_claude_settings() {
    local src="${REPO_DIR}/claude-settings.json"

    if [[ ! -f "${src}" ]]; then
        printf "[!] %s not found, skipping managed-settings install\n" "${src}" >&2
        failed=1
        return
    fi

    if [[ -e "${MANAGED_PATH}" ]]; then
        printf "[*] %s exists, skipping\n" "${MANAGED_PATH}"
        return
    fi

    sudo mkdir -p "${MANAGED_DIR}"
    sudo install -o root -g root -m 0644 "${src}" "${MANAGED_PATH}"
    printf "[*] Installed claude-settings.json -> %s (GLOBALLY MANAGED, root-owned; edit it in the repo)\n" \
        "${MANAGED_PATH}"
}

allow_bwrap_userns
install_claude_settings

# --- Untrusted-mode tool bootstrap -------------------------------------------
# Pulls the static-analysis toolchain used by untrusted-AGENTS.md.
# TODO: Replace this entire shell script with Anisble.

# name|url|sha256|kind (bin|gef|tar|zip)|target
readonly -a ANALYSIS_TOOLS=(
    "yara-x|https://github.com/VirusTotal/yara-x/releases/download/v1.19.0/yara-x-v1.19.0-x86_64-unknown-linux-gnu.tar.gz|a97d78189e3548797ac45b7b4a5fd8975783861875c594f772ec9b8bb5fa4d72|tar|/usr/local/bin/yr"
    "floss|https://github.com/mandiant/flare-floss/releases/download/quantumstrand-beta3/floss-quantumstrand-beta3-linux.zip|cec48c8504f41e0f10305d86b6e9258f63ac7aae26a9fbcec1dee1980742cf83|zip|/usr/local/bin/floss"
    "capa|https://github.com/mandiant/capa/releases/download/v9.4.0/capa-v9.4.0-linux.zip|07800a1d20a21eb18fc98716e2ae81b668e0c9a04defd588c8aa17ea3d3281e4|zip|/usr/local/bin/capa"
    "titus|https://github.com/praetorian-inc/titus/releases/download/v1.2.7/titus-linux-amd64|725b2e3c840612536c43b1c3bb7aa8e2bff659ef49474f5768af10bdfdf49cf2|bin|/usr/local/bin/titus"
    "gef|https://github.com/hugsy/gef/raw/87f359ba272e0df87b3e48ae147a82b0e3139953/gef.py|a4b10638910f0135c477d497fd63fe2f562819c19a4093eb174730d7d685d877|gef|${HOME}/.gef.py"
    "cutter|https://github.com/rizinorg/cutter/releases/download/v2.5.0/Cutter-v2.5.0-Linux-x86_64.AppImage|b8ad215d7a9e2af9e1f463511229f16e1f4745a0fb541413e5f4787f949ac0cf|bin|/usr/local/bin/cutter"
    "osv-scanner|https://github.com/google/osv-scanner/releases/download/v2.5.1/osv-scanner_linux_amd64|f9f25499a2c8cc367b3af45df2ea7eeca7fbccceab9c35079968f4b3652194be|bin|/usr/local/bin/osv-scanner"
    "uv|https://github.com/astral-sh/uv/releases/download/0.12.7/uv-x86_64-unknown-linux-gnu.tar.gz|788f18abea7c5f55d6216e4f5613fd89d4d59b631efeec117b2b07fe72f1da21|tar|/usr/local/bin/uv"
)

# package|version|python_version
readonly -a ANALYSIS_TOOLS_PYTHON=(
    "semgrep|1.175.0|"
    "guarddog|3.2.0|3.12"
    "bandit|1.9.4|"
)

fetch_analysis_tools() {
    mkdir -p "${HOME}/Downloads"

    local entry name url sha256 kind target archive dl_hash tmp
    for entry in "${ANALYSIS_TOOLS[@]}"; do
        IFS='|' read -r name url sha256 kind target <<< "${entry}"
        [[ -e "${target}" ]] && { printf "[*] %s present, skipping\n" "${name}"; continue; }

        archive="${HOME}/Downloads/$(basename "${url}")"
        [[ -f "${archive}" ]] || curl -fsSL -o "${archive}" "${url}"

        dl_hash="$(sha256sum "${archive}" | awk '{print $1}')"
        if [[ "${dl_hash}" != "${sha256}" ]]; then
            printf "[!] %s HASH MISMATCH (sha256 %s, got %s) -- not installing\n" "${name}" "${sha256}" "${dl_hash}" >&2
            failed=1
            continue
        fi

        case "${kind}" in
            bin) sudo install -m 0755 "${archive}" "${target}" ;;
            gef)
                install -m 0644 "${archive}" "${target}"
                echo "source ${target}" | tee "${HOME}/.gdbinit" >/dev/null
                ;;
            tar)
                tmp="$(mktemp -d)"
                tar -xzf "${archive}" --no-same-owner -C "${tmp}"
                find "${tmp}" -type f -perm -u+x -exec \
                    sudo install -m 0755 {} "$(dirname "${target}")/" \;
                rm -rf "${tmp}"
                ;;
            zip) sudo unzip -oq "${archive}" -d "$(dirname "${target}")" ;;
        esac
        printf "[*] %s installed -> %s\n" "${name}" "${target}"
    done
}

fetch_analysis_tools_py() {
    export PATH="${HOME}/.local/bin:${PATH}"
    export UV_PYTHON_PREFERENCE=only-managed
    export UV_PYTHON_DOWNLOADS=automatic

    if ! command -v uv >/dev/null 2>&1; then
        printf "[!] uv not on PATH, skipping python toolchain\n" >&2
        return 1
    fi
    local entry package version py_version
    local -a uv_args
    for entry in "${ANALYSIS_TOOLS_PYTHON[@]}"; do
        IFS='|' read -r package version py_version <<< "${entry}"

        if uv tool list 2>/dev/null | grep -qx "${package} v${version}"; then
            printf "[*] %s %s present, skipping\n" "${package}" "${version}"
            continue
        fi

        # Ensure any required python versions get installed.
        uv_args=(tool install "${package}==${version}")
        if [[ -n "${py_version}" ]]; then
            uv python install "${py_version}"
            uv_args+=(--python "${py_version}")
        fi

        # Send the uv_args through to uv
        if uv "${uv_args[@]}"; then
            printf "[*] %s==%s installed\n" "${package}" "${version}"
        else
            printf "[!] %s==%s FAILED\n" "${package}" "${version}" >&2
            failed=1
        fi
    done

    uv tool update-shell
    uv tool list > "${SRC_DIR}/toolchain-python.txt"
}

if [[ "${mode}" == "untrusted" ]]; then
    sudo apt-get update -y && sudo apt-get install -y curl unzip tar gdb jq
    fetch_analysis_tools
    fetch_analysis_tools_py
fi

exit "${failed}"
