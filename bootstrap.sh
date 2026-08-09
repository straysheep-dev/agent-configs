#!/bin/bash

# SPDX-License-Identifier: MIT

# Requires sudo to install the managed-settings.json config.

set -euo pipefail

readonly SRC_DIR="${HOME}/src"
readonly REPO_DIR="${HOME}/src/agent-configs"

mode="trusted"
case "${1:-}" in
    --untrusted) mode="untrusted" ;;
    --trusted|"") mode="trusted" ;;
    *)
        printf "[!] Unknown flag '%s'. Usage: %s [--trusted|--untrusted]\n" "${1}" "$0" >&2
        exit 1
        ;;
esac
readonly mode

prefix="global"
[[ "${mode}" == "untrusted" ]] && prefix="untrusted"
readonly prefix

config_list="${prefix}-CLAUDE.md
${prefix}-SESSION.md
${prefix}-TODO.md"

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

printf "[*] Bootstrapping in %s mode\n" "${mode}"

for file in ${config_list}
do
    target_name="${file#"${prefix}"-}"  # strip "<prefix>-" prefix
    target_path="${SRC_DIR}/${target_name}"

    if [[ -e "${target_path}" || -L "${target_path}" ]]; then
        if [[ -L "${target_path}" ]]; then
            current_target="$(readlink "${target_path}")"
            if [[ "${current_target}" != *"/${file}" ]]; then
                printf "[!] %s is linked to a DIFFERENT mode (%s). Remove it manually to switch to %s.\n" \
                    "${target_path}" "${current_target}" "${mode}" >&2
                continue
            fi
        fi
        printf "[*] %s exists, skipping...\n" "${target_path}"
    else
        ln -s "${REPO_DIR}/${file}" "${target_path}"
        printf "[*] Symlinking %s -> %s...\n" "${file}" "${target_path}"
    fi
done

# Install settings.json as a root-owned, globally managed config.
# Users can read it, but only root can write it -- changes belong in the repo, not in the dev environment.
readonly MANAGED_DIR="/etc/claude-code"
readonly MANAGED_PATH="${MANAGED_DIR}/managed-settings.json"

if [[ -f "${REPO_DIR}/settings.json" ]]; then
    sudo mkdir -p "${MANAGED_DIR}"
    sudo install -o root -g root -m 0644 "${REPO_DIR}/settings.json" "${MANAGED_PATH}"
    printf "[*] Installed %s as a GLOBALLY MANAGED config (root-owned, edit it in the repo, not in this environment)\n" "${MANAGED_PATH}"
else
    printf "[!] %s/settings.json not found, skipping managed-settings install\n" "${REPO_DIR}" >&2
fi