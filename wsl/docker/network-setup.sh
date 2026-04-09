#!/usr/bin/env bash
set -euo pipefail

echo "==> Restarting docker to apply daemon.json"
if command -v systemctl &>/dev/null; then
  sudo systemctl restart docker
else
  sudo service docker restart || true
fi

docker network ls
