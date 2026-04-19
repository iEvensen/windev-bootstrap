#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$HOME/windev-bootstrap}"

if k3d cluster list 2>/dev/null | grep -q "^dev "; then
  echo "k3d cluster 'dev' already exists, skipping creation."
else
  k3d cluster create --config "$REPO_ROOT/wsl/k3d/k3d-dev.yaml"
fi

# Enable Traefik dashboard on the traefik entrypoint (port 9000)
kubectl apply -f "$REPO_ROOT/wsl/k3d/traefik-config.yaml"
echo "Waiting for Traefik to redeploy with dashboard enabled..."
kubectl rollout status deploy/traefik -n kube-system --timeout=120s
