#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$HOME/windev-bootstrap}"

echo "==> Docker: installing engine"
sudo apt install -y docker.io docker-compose-plugin

echo "==> Adding user to docker group"
sudo usermod -aG docker "$USER"

echo "==> Configuring Docker daemon"
sudo mkdir -p /etc/docker
sudo cp "$REPO_ROOT/wsl/docker/daemon.json" /etc/docker/daemon.json

echo "==> Enabling systemd docker service (if systemd enabled in WSL)"
if command -v systemctl &>/dev/null; then
  sudo systemctl enable docker
  sudo systemctl restart docker
else
  echo "systemd not active; you may need to start docker manually in WSL."
fi

echo "==> Installing k3d"
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

echo "==> Installing kubectl"
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/kubectl

echo "==> Creating project directories"
mkdir -p "$HOME/projects/workspace"

echo "==> Linking dotfiles"
ln -sf "$REPO_ROOT/dotfiles/.gitconfig" "$HOME/.gitconfig"
ln -sf "$REPO_ROOT/dotfiles/.gitignore_global" "$HOME/.gitignore_global"

echo "==> Git global ignore"
git config --global core.excludesfile "$HOME/.gitignore_global"

echo "==> Configuring git identity"
if [ -z "$(git config --global user.name)" ]; then
  read -rp "Git user name: " GIT_NAME
  git config --global user.name "$GIT_NAME"
fi
if [ -z "$(git config --global user.email)" ]; then
  read -rp "Git email: " GIT_EMAIL
  git config --global user.email "$GIT_EMAIL"
fi

echo "==> Done."
