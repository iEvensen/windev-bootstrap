#!/usr/bin/env bash
set -euo pipefail

echo "==> Installing GitHub CLI"
if ! command -v gh &>/dev/null; then
  type -p curl >/dev/null || sudo apt install -y curl
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | \
    sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
  sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | \
    sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
  sudo apt update
  sudo apt install -y gh
fi

echo "==> gh auth login (interactive)"
gh auth login

echo "==> Generating SSH key (if missing)"
if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
  ssh-keygen -t ed25519 -C "your-email@example.com" -f "$HOME/.ssh/id_ed25519" -N ""
  gh ssh-key add "$HOME/.ssh/id_ed25519.pub" -t "WSL Dev Machine"
fi
