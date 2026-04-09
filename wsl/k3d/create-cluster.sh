#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$HOME/windev-bootstrap}"

k3d cluster create --config "$REPO_ROOT/wsl/k3d/k3d-dev.yaml"
