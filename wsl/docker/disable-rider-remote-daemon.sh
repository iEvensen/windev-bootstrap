#!/usr/bin/env bash
set -euo pipefail

# Companion helper for enable-rider-remote-daemon.sh.
# Removes the Docker systemd override, removes the 'hosts' key from daemon.json,
# restarts Docker, unmasks docker.socket, and removes iptables rules for port 2375.

echo "==> Disable Rider/Testcontainers Docker TCP endpoint (WSL2)"

if [[ $EUID -eq 0 ]]; then
  echo "Run this script as a regular user (sudo is used internally)."
  exit 1
fi

if ! command -v systemctl >/dev/null 2>&1; then
  echo "systemctl not found. This requires a systemd-enabled WSL distro."
  exit 1
fi

OVERRIDE_FILE="/etc/systemd/system/docker.service.d/override.conf"
DAEMON_JSON="/etc/docker/daemon.json"

echo "==> Removing docker.service override (if present)"
if [[ -f "$OVERRIDE_FILE" ]]; then
  sudo rm -f "$OVERRIDE_FILE"
else
  echo "    No override file found at $OVERRIDE_FILE"
fi

echo "==> Removing 'hosts' key from ${DAEMON_JSON} (if present)"
if [[ -f "$DAEMON_JSON" ]]; then
  CURRENT_JSON="$(sudo cat "$DAEMON_JSON")"
  echo "$CURRENT_JSON" | jq 'del(.hosts)' | sudo tee "${DAEMON_JSON}.tmp" >/dev/null
  sudo mv "${DAEMON_JSON}.tmp" "$DAEMON_JSON"
fi

echo "==> Reloading systemd"
sudo systemctl daemon-reload

echo "==> Re-enabling docker.socket"
sudo systemctl enable docker.socket >/dev/null 2>&1 || true
sudo systemctl start docker.socket >/dev/null 2>&1 || true

echo "==> Restarting docker.service"
sudo systemctl reset-failed docker.service >/dev/null 2>&1 || true
sudo systemctl restart docker.service

if command -v iptables >/dev/null 2>&1; then
  echo "==> Removing INPUT firewall rules for tcp/2375 (if present)"
  while IFS= read -r rule; do
    [[ -z "$rule" ]] && continue
    delete_rule="${rule/-A /-D }"
    # shellcheck disable=SC2086
    sudo iptables $delete_rule || true
  done < <(sudo iptables -S INPUT | grep -- "-p tcp -m tcp --dport 2375" || true)
else
  echo "==> iptables not found, skipping firewall cleanup"
fi

echo "==> Validating service"
sudo systemctl --no-pager --full status docker.service | sed -n '1,20p'

echo "==> Checking for active listener on port 2375"
if sudo ss -lntp | grep -q ':2375'; then
  echo "WARNING: Found a process still listening on 2375"
  sudo ss -lntp | grep ':2375' || true
  echo "Check docker service logs: sudo journalctl -u docker.service --no-pager -n 200"
else
  echo "OK: No listener found on port 2375"
fi

echo
echo "Done. Rider/Testcontainers TCP endpoint is disabled unless re-enabled."
