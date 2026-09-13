#!/bin/bash

# SPDX-License-Identifier: MIT
# Assisted-by: Claude:claude-sonnet-5

# Requires sudo for network monitoring

set -uo pipefail

SESSION="netreview"
PCAP="outbound_all_$(date +%s).pcap"
FILTER='(tcp or udp or icmp) and not src net (127.0.0.0/8 or 169.254.0.0/16)'
TCPCONNECT_BIN="$(command -v tcpconnect.bt || printf '%s\n' /usr/share/bpftrace/tools/tcpconnect.bt)"

tmux kill-session -t "$SESSION" 2>/dev/null

# Pcap capture runs silently in the background
sudo tcpdump -i any -n -U "$FILTER" -w "$PCAP" > /dev/null 2>&1 &
TCPDUMP_PID=$!
printf '%s\n' "tcpdump capturing to $PCAP (pid $TCPDUMP_PID)"

# Clean up the background capture when this script exits
trap 'sudo kill "$TCPDUMP_PID" 2>/dev/null' EXIT

# Decide whether bpftrace is actually usable before starting tmux
bpf_available() {
  [[ -x "$TCPCONNECT_BIN" ]] || return 1

  local lockdown
  lockdown="$(cat /sys/kernel/security/lockdown 2>/dev/null || printf '')"
  # File format: "none [integrity] confidentiality", brackets mark active mode
  if [[ "$lockdown" == *"[confidentiality]"* ]]; then
    return 1
  fi

  [[ -r /sys/kernel/btf/vmlinux ]] || return 1

  return 0
}

if bpf_available; then
  printf '%s\n' "bpftrace available, using tcpconnect.bt for live view"
  PANE0_CMD="sudo $TCPCONNECT_BIN"
else
  printf '%s\n' "bpftrace unavailable (kernel lockdown/BPF restriction), falling back to tcpdump live decode"
  PANE0_CMD="sudo tcpdump -i any -n -tttt -l '$FILTER'"
fi

# Pane 0: per-connection view (bpftrace or tcpdump fallback)
tmux new-session -d -s "$SESSION" -n main "$PANE0_CMD"

# Pane 1: DNS query/response log, assumes systemd-resolved is the resolver
tmux split-window -v -t "$SESSION" "sudo resolvectl monitor"

tmux select-layout -t "$SESSION" even-vertical

# Nesting an attach inside an existing tmux session prints a warning and
# refuses by default; switch-client moves the current client over cleanly.
if [[ -n "${TMUX:-}" ]]; then
  tmux switch-client -t "$SESSION"
else
  tmux attach -t "$SESSION"
fi
