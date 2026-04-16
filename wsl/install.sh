#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$HOME/windev-bootstrap}"

# --- Export corporate CA certificates from Windows cert store ---
CERT_DIR="$REPO_ROOT/certs"
mkdir -p "$CERT_DIR"
echo "==> Checking Windows certificate store for corporate CA certificates"
if command -v powershell.exe &>/dev/null; then
  # Export non-default root CAs (filter out well-known public CAs by checking
  # for certs whose issuer == subject, i.e. self-signed roots, that are NOT
  # shipped with Windows by default — heuristic: subject contains org domain keywords)
  powershell.exe -NoProfile -Command '
    $known = @("Microsoft","Comodo","DigiCert","GlobalSign","VeriSign","ISRG",
      "Starfield","Go Daddy","GoDaddy","Buypass","Certum","USERTrust","SECOM",
      "Sectigo","Symantec","AAA Certificate","Security Communication","Class 3 Public Primary")
    $certs = Get-ChildItem Cert:\LocalMachine\Root | Where-Object {
      $dominated = $false
      foreach ($k in $known) { if ($_.Subject -like "*$k*") { $dominated = $true; break } }
      -not $dominated -and $_.NotAfter -gt (Get-Date)
    }
    foreach ($c in $certs) {
      $name = ($c.Subject -replace "CN=","" -split ",")[0].Trim() -replace "[^a-zA-Z0-9._-]","_"
      $pem = "-----BEGIN CERTIFICATE-----"
      $pem += [Environment]::NewLine
      $pem += [Convert]::ToBase64String($c.RawData, "InsertLineBreaks")
      $pem += [Environment]::NewLine
      $pem += "-----END CERTIFICATE-----"
      Write-Output "===CERT:${name}==="
      Write-Output $pem
    }
  ' | awk '
    /^===CERT:/ {
      match($0, /===CERT:(.+)===/, m)
      file = "'"$CERT_DIR"'/" m[1] ".crt"
      next
    }
    file { print > file }
    /^-----END CERTIFICATE-----/ { close(file); file="" }
  '
  cert_count=$(find "$CERT_DIR" -name "*.crt" 2>/dev/null | wc -l)
  echo "    Exported $cert_count certificate(s) from Windows store"
else
  echo "    powershell.exe not found; skipping Windows cert export"
fi

# --- Install corporate CA certificates (if present) ---
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
