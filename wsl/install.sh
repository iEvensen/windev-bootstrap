#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$HOME/windev-bootstrap}"

echo "==> Updating apt"
sudo apt update

echo "==> Installing base packages"
sudo apt install -y \
  ca-certificates curl gnupg lsb-release \
  git zsh build-essential \
  apt-transport-https software-properties-common

echo "==> Running Ubuntu setup"
bash "$REPO_ROOT/wsl/ubuntu-setup.sh"

echo "==> Setting zsh as default shell"
chsh -s "$(command -v zsh)"

echo "==> Done. Restart your WSL session."
