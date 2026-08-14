#!/usr/bin/env bash
set -euo pipefail

# Install or start Portainer CE for the local Docker Engine inside WSL.
# This keeps Portainer independent from k3d lifecycle and avoids exposing it publicly.

CONTAINER_NAME="portainer"
PORTAINER_IMAGE="portainer/portainer-ce:lts"
PORTAINER_DATA_DIR="/var/lib/portainer"
PORTAINER_BIND_IP="127.0.0.1"
PORTAINER_PORT="9443"

if [[ $EUID -eq 0 ]]; then
  echo "Run this script as a regular user (sudo is used internally)."
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "docker not found. Install Docker Engine in WSL first."
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "Docker daemon is not reachable. Start Docker first."
  exit 1
fi

echo "==> Preparing Portainer data directory"
sudo mkdir -p "$PORTAINER_DATA_DIR"
sudo chown "$USER":"$USER" "$PORTAINER_DATA_DIR"

echo "==> Pulling Portainer image"
docker pull "$PORTAINER_IMAGE"

if docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
  echo "==> Existing container '$CONTAINER_NAME' found"
  if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    echo "    Container is already running"
  else
    echo "    Starting existing container"
    docker start "$CONTAINER_NAME" >/dev/null
  fi
else
  echo "==> Creating Portainer container"
  docker run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    -p "${PORTAINER_BIND_IP}:${PORTAINER_PORT}:9443" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "${PORTAINER_DATA_DIR}:/data" \
    "$PORTAINER_IMAGE" >/dev/null
fi

echo "==> Validating listener"
if ss -lnt | grep -q "${PORTAINER_BIND_IP}:${PORTAINER_PORT}"; then
  echo "OK: Portainer is listening on ${PORTAINER_BIND_IP}:${PORTAINER_PORT}"
else
  echo "WARNING: Listener check did not find ${PORTAINER_BIND_IP}:${PORTAINER_PORT}"
fi

echo
echo "Portainer URL: https://localhost:${PORTAINER_PORT}"
echo "Note: Browser will show a self-signed cert warning on first access."
echo "Optional next step: run ./wsl/docker/prepare-portainer-k3d-access.sh to attach k3d."