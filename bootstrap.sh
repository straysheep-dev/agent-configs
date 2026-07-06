#!/bin/bash

# SPDX-License-Identifier: MIT

# Requires sudo to install the managed-settings.json config.

set -euo pipefail

config_list='global-CLAUDE.md
global-SESSION.md
global-TODO.md'

readonly SRC_DIR="${HOME}/src"
readonly REPO_DIR="${HOME}/src/agent-configs"

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

for file in ${config_list}
do
    target_name="${file#global-}"  # strip "global-" prefix
    target_path="${SRC_DIR}/${target_name}"

    if [[ -e "${target_path}" || -L "${target_path}" ]]; then
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
