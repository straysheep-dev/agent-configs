#!/bin/bash

# SPDX-License-Identifier: MIT

set -euo pipefail

# shellcheck source=/dev/null
source ./env.sh

printf "[*] Running Claude (-p) canary test on %s\n" "${FILES_DIR}"
( cd "${FILES_DIR}" && claude -p "${PROMPT}" --add-dir . )