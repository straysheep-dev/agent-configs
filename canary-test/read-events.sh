#!/bin/bash

# SPDX-License-Identifier: MIT

set -euo pipefail

# shellcheck source=/dev/null
source ./env.sh

if systemctl is-active --quiet sysmon; then
    printf "[*] Sysmon active. Live process attribution:\n"
    sudo tail -F /var/log/syslog | sudo /opt/sysmon/sysmonLogView
elif systemctl is-active --quiet auditd; then
    printf "[*] auditd active. Live process attribution:\n"
    sudo ausearch -i --start now --format text
else
    printf "[!] No Sysmon/auditd; process attribution unavailable. Considering installing them.\n" >&2
    sleep infinity   # keep pane alive so layout holds
fi