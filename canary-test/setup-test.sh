#!/bin/bash

# SPDX-License-Identifier: MIT

# Requires sudo to run the canary tests.

set -euo pipefail

# shellcheck source=env.sh
source ./env.sh

if [[ ! -f "${OS_RELEASE}" ]]; then
    printf "[!] %s not found, cannot determine unbound conf path. Exiting.\n" "${OS_RELEASE}" >&2
    exit 1
fi

# shellcheck source=/dev/null
source "${OS_RELEASE}"

case "${ID_LIKE:-$ID}" in
    *debian*) UNBOUND_CONF_DIR="/etc/unbound/unbound.conf.d"; PKG_INSTALL="apt-get install -y unbound" ;;
    *rhel*|*fedora*) UNBOUND_CONF_DIR="/etc/unbound/conf.d"; PKG_INSTALL="dnf install -y unbound" ;;
    *)
        printf "[!] Unsupported OS family '%s'. Exiting.\n" "${ID_LIKE:-$ID}" >&2
        exit 1
        ;;
esac
readonly UNBOUND_CONF_DIR PKG_INSTALL
readonly UNBOUND_PATH="${UNBOUND_CONF_DIR}/unbound-canary-test.conf"

install_and_start_unbound() {
    if ! command -v unbound >/dev/null 2>&1; then
        printf "[*] unbound not installed, installing...\n"
        # shellcheck disable=SC2086
        sudo ${PKG_INSTALL}
    fi
    sudo mkdir -p "${UNBOUND_CONF_DIR}"
    if [[ -f "${UNBOUND_PATH}" ]]; then
        printf "[*] %s exists, overwriting with current canary config...\n" "${UNBOUND_PATH}"
    fi
    sed "s/IP_PLACEHOLDER/${SINKHOLE_IP}/" ./unbound-canary-test.conf \
        | sudo tee "${UNBOUND_PATH}" >/dev/null
    sudo unbound-checkconf
    sudo systemctl enable --now unbound
    sudo systemctl restart unbound
    printf "[*] unbound restarted with canary record loaded (sinkhole: %s)\n" "${SINKHOLE_IP}"
}

# Testing utilities, to actively validate controls.
if systemctl is-active --quiet unbound; then
    install_and_start_unbound
elif systemctl is-active --quiet systemd-resolved; then
    printf "[*] systemd-resolved active, it can't log qnames the way this test needs.\n"
    printf "[*] Disabling it and switching to unbound.\n"
    sudo systemctl disable --now systemd-resolved
    sudo rm -f /etc/resolv.conf
    echo "nameserver 127.0.0.1" | sudo tee /etc/resolv.conf >/dev/null
    install_and_start_unbound
else
    printf "[!] No DNS daemon running that we can log to. Installing unbound.\n" >&2
    install_and_start_unbound
fi

printf "[*] Switching over to tmux...\n"

sleep 3

# Launch tmux so we're ready
tmux kill-session -t "${SESSION}" 2>/dev/null || true
tmux new-session -d -s "${SESSION}"

# Pane 0: capture + live wire (auto)
tmux send-keys -t "${SESSION}" "sudo bash ./run-capture.sh" C-m

# Pane 1: process attribution (auto)
tmux split-window -v -t "${SESSION}"
tmux send-keys -t "${SESSION}" "sudo bash ./read-events.sh" C-m

# Pane 2: driver -- loaded, doesn't run until you press enter
tmux split-window -v -t "${SESSION}"
tmux send-keys -t "${SESSION}" "./run-test.sh"   # no C-m: you press enter

tmux select-layout -t "${SESSION}" even-vertical
tmux select-pane -t "${SESSION}.2"
tmux attach -t "${SESSION}"