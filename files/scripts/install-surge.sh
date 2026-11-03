#!/usr/bin/env bash
set -euo pipefail

curl -fsSL https://surgedm.github.io/install \
    | env -u SHELL SURGE_INSTALL_DIR=/usr/bin sh
