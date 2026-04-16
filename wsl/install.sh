#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$HOME/windev-bootstrap}"

# --- Install corporate CA certificates (if present in certs/) ---
CERT_DIR="$REPO_ROOT/certs"
if ls "$CERT_DIR"/*.crt &>/dev/null; then
  echo "==> Installing corporate CA certificates"
  sudo cp "$CERT_DIR"/*.crt /usr/local/share/ca-certificates/
  sudo update-ca-certificates

  # Point all tools at the system CA bundle (now includes corporate certs)
  CA_BUNDLE="/etc/ssl/certs/ca-certificates.crt"

  # Node.js / npm
  export NODE_EXTRA_CA_CERTS="$CA_BUNDLE"
  # Python (pip, requests, httpx, urllib3)
  export PIP_CERT="$CA_BUNDLE"
  export REQUESTS_CA_BUNDLE="$CA_BUNDLE"
  export SSL_CERT_FILE="$CA_BUNDLE"
  # curl / wget
  export CURL_CA_BUNDLE="$CA_BUNDLE"
  # Git
  git config --global http.sslCAInfo "$CA_BUNDLE"
  # .NET
  export SSL_CERT_DIR="/etc/ssl/certs"
  # Azure CLI
  export AZURE_CLI_DISABLE_CONNECTION_VERIFICATION=0
  export ADAL_PYTHON_SSL_NO_VERIFY=0
  export AZURE_CA_BUNDLE="$CA_BUNDLE"
  # Pulumi
  export PULUMI_CA_BUNDLE="$CA_BUNDLE"

  # Persist for future shells (login + non-login)
  sudo tee /etc/profile.d/corp-certs.sh > /dev/null <<EOF
export NODE_EXTRA_CA_CERTS="$CA_BUNDLE"
export PIP_CERT="$CA_BUNDLE"
export REQUESTS_CA_BUNDLE="$CA_BUNDLE"
export SSL_CERT_FILE="$CA_BUNDLE"
export CURL_CA_BUNDLE="$CA_BUNDLE"
export SSL_CERT_DIR="/etc/ssl/certs"
export AZURE_CLI_DISABLE_CONNECTION_VERIFICATION=0
export ADAL_PYTHON_SSL_NO_VERIFY=0
export AZURE_CA_BUNDLE="$CA_BUNDLE"
export PULUMI_CA_BUNDLE="$CA_BUNDLE"
EOF
fi

# --- Switch apt sources to HTTPS (required for Checkpoint transparent inspection) ---
echo "==> Switching apt sources to HTTPS"
for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.list; do
  [ -f "$f" ] && sudo sed -i 's|http://archive\.ubuntu\.com|https://archive.ubuntu.com|g; s|http://security\.ubuntu\.com|https://security.ubuntu.com|g' "$f"
done
# Also handle the newer DEB822 .sources format (Ubuntu 24.04+)
for f in /etc/apt/sources.list.d/*.sources; do
  [ -f "$f" ] && sudo sed -i 's|http://archive\.ubuntu\.com|https://archive.ubuntu.com|g; s|http://security\.ubuntu\.com|https://security.ubuntu.com|g' "$f"
done

# --- Add Microsoft .NET package repository (alternative mirror) ---
echo "==> Adding Microsoft package repository"
if [ ! -f /etc/apt/sources.list.d/microsoft-prod.list ]; then
  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /etc/apt/keyrings/microsoft.gpg > /dev/null
  echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/ubuntu/$(lsb_release -rs)/prod $(lsb_release -cs) main" | \
    sudo tee /etc/apt/sources.list.d/microsoft-prod.list > /dev/null
  # Keep Microsoft low priority for most packages, but allow dotnet fallback
  sudo tee /etc/apt/preferences.d/microsoft-prod.pref > /dev/null <<'PREF'
Package: *
Pin: origin packages.microsoft.com
Pin-Priority: 100

Package: dotnet* aspnetcore*
Pin: origin packages.microsoft.com
Pin-Priority: 500
PREF
  echo "    Microsoft repository added (fallback priority)"
else
  echo "    Microsoft repository already configured"
fi

echo "==> Updating apt"
sudo apt update

# Hold Ubuntu-packaged dotnet to avoid upgrade failures (dotnet is managed via install scripts)
dpkg -l 'dotnet*' 'aspnetcore*' 2>/dev/null | awk '/^ii/ {print $2}' | xargs -r sudo apt-mark hold 2>/dev/null || true

echo "==> Upgrading packages"
sudo apt upgrade -y || {
  echo "    apt upgrade failed, retrying with --fix-missing..."
  sudo apt update
  sudo apt upgrade -y --fix-missing || echo "    WARNING: apt upgrade failed; continuing with existing packages"
}

echo "==> Installing base packages"
sudo apt install -y \
  ca-certificates curl gnupg lsb-release \
  git build-essential unzip tar \
  apt-transport-https software-properties-common

echo "==> Running Ubuntu setup"
bash "$REPO_ROOT/wsl/ubuntu-setup.sh"

echo "==> Done. Restart your WSL session."
