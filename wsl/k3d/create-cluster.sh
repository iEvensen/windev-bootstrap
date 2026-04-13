#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$HOME/windev-bootstrap}"

if k3d cluster list 2>/dev/null | grep -q "^dev "; then
  echo "k3d cluster 'dev' already exists, skipping creation."
else
  k3d cluster create --config "$REPO_ROOT/wsl/k3d/k3d-dev.yaml"
fi
