#!/usr/bin/env bash
set -euo pipefail

# Optional helper for Rider/Testcontainers users running Docker Engine inside WSL.
# Merges the 'hosts' key into /etc/docker/daemon.json (preserving all other settings).
# Masks docker.socket and uses a minimal systemd override to strip the default -H fd:// flag.

BIND_IP="127.0.0.1"
BIND_ALL="false"
ALLOW_FROM=""
ALLOW_INSECURE_PUBLIC_BIND="false"
ALLOW_INSECURE_NO_FIREWALL="false"

is_valid_ipv4() {
  local ip="$1"
  local IFS='.'
  local parts

  read -r -a parts <<< "$ip"
  if [[ ${#parts[@]} -ne 4 ]]; then
    return 1
  fi

  for part in "${parts[@]}"; do
    if ! [[ "$part" =~ ^[0-9]{1,3}$ ]]; then
      return 1
    fi
    if ((part < 0 || part > 255)); then
      return 1
    fi
  done

  return 0
}

detect_windows_host_ip() {
  ip route show default 2>/dev/null | awk '/default/ {print $3; exit}'
}

usage() {
  cat <<'EOF'
Usage:
  ./wsl/docker/enable-rider-remote-daemon.sh [--bind <ip>] [--allow-from <ip>] [--bind-all] [--allow-insecure-public-bind] [--allow-insecure-no-firewall]

Options:
  --bind <ip>                     Bind Docker TCP listener to a specific IPv4 address.
  --allow-from <ip>               Allowed source IPv4 for port 2375 firewall rule.
  --bind-all                      Bind to 0.0.0.0:2375 (least secure; all interfaces).
  --allow-insecure-public-bind    Required with --bind-all.
  --allow-insecure-no-firewall    Allow non-loopback bind without firewall restriction.
  -h, --help                      Show this help.

Defaults:
  - Default bind is 127.0.0.1 (most secure).
  - For non-loopback binds, the script tries to restrict source IP to the Windows host.

Notes:
  - This is intended for local development with Rider/Testcontainers.
  - Port 2375 has no TLS or authentication. Use only on trusted networks.
EOF
}

while (($# > 0)); do
  case "$1" in
    --bind)
      shift
      if (($# == 0)); then
        echo "ERROR: --bind requires an IP argument."
        exit 1
      fi
      BIND_IP="$1"
      ;;
    --allow-from)
      shift
      if (($# == 0)); then
        echo "ERROR: --allow-from requires an IP argument."
        exit 1
      fi
      ALLOW_FROM="$1"
      ;;
    --bind-all)
      BIND_ALL="true"
      ;;
    --allow-insecure-public-bind)
      ALLOW_INSECURE_PUBLIC_BIND="true"
      ;;
    --allow-insecure-no-firewall)
      ALLOW_INSECURE_NO_FIREWALL="true"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
  shift
done

echo "==> Configure Docker daemon for Rider/Testcontainers (WSL2, no Docker Desktop)"

if [[ $EUID -eq 0 ]]; then
  echo "Run this script as a regular user (sudo is used internally)."
  exit 1
fi

if ! command -v systemctl >/dev/null 2>&1; then
  echo "systemctl not found. This requires a systemd-enabled WSL distro."
  echo "Check /etc/wsl.conf and enable systemd if needed."
  exit 1
fi

if ! command -v dockerd >/dev/null 2>&1; then
  echo "dockerd not found. Install Docker Engine in WSL first."
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq not found. Install jq first: sudo apt install -y jq"
  exit 1
fi

if [[ "$BIND_ALL" == "true" ]]; then
  if [[ "$ALLOW_INSECURE_PUBLIC_BIND" != "true" ]]; then
    echo "ERROR: --bind-all requires --allow-insecure-public-bind."
    exit 1
  fi
  BIND_IP="0.0.0.0"
  echo "WARNING: Binding to 0.0.0.0 exposes Docker TCP on all interfaces"
fi

if ! is_valid_ipv4 "$BIND_IP"; then
  echo "ERROR: Invalid --bind IPv4 address: $BIND_IP"
  exit 1
fi

if [[ -n "$ALLOW_FROM" ]] && ! is_valid_ipv4 "$ALLOW_FROM"; then
  echo "ERROR: Invalid --allow-from IPv4 address: $ALLOW_FROM"
  exit 1
fi

echo "==> Using TCP bind: ${BIND_IP}:2375"

if [[ "$BIND_IP" != "127.0.0.1" ]]; then
  if [[ -z "$ALLOW_FROM" ]]; then
    ALLOW_FROM="$(detect_windows_host_ip || true)"
  fi

  if [[ -n "$ALLOW_FROM" ]] && ! is_valid_ipv4 "$ALLOW_FROM"; then
    echo "ERROR: Detected invalid source IP: $ALLOW_FROM"
    exit 1
  fi

  if [[ -z "$ALLOW_FROM" ]] && [[ "$ALLOW_INSECURE_NO_FIREWALL" != "true" ]]; then
    echo "ERROR: Could not detect Windows host IP for firewall restriction."
    echo "Use --allow-from <windows-ip> or --allow-insecure-no-firewall."
    exit 1
  fi
fi

DAEMON_JSON="/etc/docker/daemon.json"
echo "==> Merging hosts into ${DAEMON_JSON}"
if [[ ! -f "$DAEMON_JSON" ]]; then
  echo '{}' | sudo tee "$DAEMON_JSON" >/dev/null
fi
NEW_HOSTS="[\"unix:///var/run/docker.sock\", \"tcp://${BIND_IP}:2375\"]"
CURRENT_JSON="$(sudo cat "$DAEMON_JSON")"
echo "$CURRENT_JSON" | jq --argjson hosts "$NEW_HOSTS" '. + {hosts: $hosts}' | \
  sudo tee "${DAEMON_JSON}.tmp" >/dev/null
sudo mv "${DAEMON_JSON}.tmp" "$DAEMON_JSON"

echo "==> Creating systemd override directory"
sudo mkdir -p /etc/systemd/system/docker.service.d

echo "==> Writing docker.service override (strips -H fd:// and removes socket dependency)"
cat <<'EOF' | sudo tee /etc/systemd/system/docker.service.d/override.conf >/dev/null
[Unit]
After=network-online.target containerd.service
Wants=network-online.target

[Service]
ExecStart=
ExecStart=/usr/bin/dockerd --containerd=/run/containerd/containerd.sock
EOF

echo "==> Reloading systemd"
sudo systemctl daemon-reload

echo "==> Stopping and disabling docker.socket"
sudo systemctl stop docker.socket >/dev/null 2>&1 || true
sudo systemctl disable docker.socket >/dev/null 2>&1 || true

if [[ "$BIND_IP" != "127.0.0.1" ]]; then
  if command -v iptables >/dev/null 2>&1 && [[ -n "$ALLOW_FROM" ]]; then
    echo "==> Applying firewall restriction for port 2375"
    sudo iptables -C INPUT -p tcp --dport 2375 -s "$ALLOW_FROM" -j ACCEPT >/dev/null 2>&1 || \
      sudo iptables -I INPUT 1 -p tcp --dport 2375 -s "$ALLOW_FROM" -j ACCEPT
    sudo iptables -C INPUT -p tcp --dport 2375 -j DROP >/dev/null 2>&1 || \
      sudo iptables -A INPUT -p tcp --dport 2375 -j DROP
    echo "==> Allowed source for 2375: $ALLOW_FROM"
  elif [[ "$ALLOW_INSECURE_NO_FIREWALL" == "true" ]]; then
    echo "WARNING: Non-loopback bind without firewall restriction"
  else
    echo "ERROR: iptables is required for non-loopback binds unless --allow-insecure-no-firewall is set."
    exit 1
  fi
fi

echo "==> Starting docker.service"
sudo systemctl reset-failed docker.service >/dev/null 2>&1 || true
sudo systemctl restart docker.service

echo "==> Validating service"
sudo systemctl --no-pager --full status docker.service | sed -n '1,20p'

echo "==> Verifying listener on port 2375"
if sudo ss -lntp | grep -q ':2375'; then
  sudo ss -lntp | grep ':2375' || true
else
  echo "ERROR: No listener found on port 2375."
  echo "Check logs: sudo journalctl -u docker.service --no-pager -n 200"
  exit 1
fi

echo
echo "Done."
echo "Use this Docker endpoint in Rider/Testcontainers:"
echo "  tcp://${BIND_IP}:2375"
echo
echo "Test from Windows PowerShell:"
echo "  Test-NetConnection ${BIND_IP} -Port 2375"
echo
echo "Optional Testcontainers file on Windows:"
echo "  C:\\Users\\<user>\\.testcontainers.properties"
echo "  docker.host=tcp://${BIND_IP}:2375"
echo
echo "Security note: port 2375 is unauthenticated and unencrypted (no TLS)."
if [[ "$BIND_IP" == "127.0.0.1" ]]; then
  echo "Current mode: loopback-only bind (recommended)."
elif [[ -n "$ALLOW_FROM" ]]; then
  echo "Current mode: non-loopback bind restricted to source ${ALLOW_FROM}."
else
  echo "Current mode: non-loopback bind without firewall restriction."
fi
