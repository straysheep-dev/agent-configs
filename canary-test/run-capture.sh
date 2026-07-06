#!/bin/bash

# SPDX-License-Identifier: MIT

set -euo pipefail

# shellcheck source=/dev/null
source ./env.sh

sudo mkdir -p "${PCAP_DIR}"

TIME_STAMP="$(date +%Y%m%dT%H%M%SZ)"
readonly TIME_STAMP
readonly PCAP_RUN="${PCAP_DIR}/canary-test-${TIME_STAMP}.pcap"

# -U flushes each packet to disk at once so the live reader sees it immediately.
sudo tcpdump -ni any -U -w "${PCAP_RUN}" \
    "host ${SINKHOLE_IP} or (port 53 and not host 127.0.0.1)" &

# Follow the growing capture without stopping at EOF.
sudo tail -F "${PCAP_RUN}" | sudo tcpdump -nl -r -
