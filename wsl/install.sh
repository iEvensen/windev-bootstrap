#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$HOME/windev-bootstrap}"

# --- Install corporate CA certificates (if present) ---
CERT_DIR="$REPO_ROOT/certs"
if [ -d "$CERT_DIR" ] && ls "$CERT_DIR"/*.crt &>/dev/null; then
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

echo "==> Updating apt"
sudo apt update

echo "==> Upgrading packages"
sudo apt upgrade -y

echo "==> Installing base packages"
sudo apt install -y \
  ca-certificates curl gnupg lsb-release \
  git build-essential unzip tar \
  apt-transport-https software-properties-common

echo "==> Running Ubuntu setup"
bash "$REPO_ROOT/wsl/ubuntu-setup.sh"

echo "==> Done. Restart your WSL session."
