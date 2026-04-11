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

echo "==> Creating k3d cluster"
bash "$REPO_ROOT/wsl/k3d/create-cluster.sh"

echo "==> Creating project directories"
mkdir -p "$HOME/projects/workspace"

echo "==> Linking dotfiles"
ln -sf "$REPO_ROOT/dotfiles/.gitconfig" "$HOME/.gitconfig"
ln -sf "$REPO_ROOT/dotfiles/.gitignore_global" "$HOME/.gitignore_global"

echo "==> Git global ignore"
git config --global core.excludesfile "$HOME/.gitignore_global"

echo "==> Applying VS Code settings for Remote-WSL"
VSCODE_MACHINE_DIR="$HOME/.vscode-server/data/Machine"
mkdir -p "$VSCODE_MACHINE_DIR"
cp "$REPO_ROOT/vscode/settings.json" "$VSCODE_MACHINE_DIR/settings.json"

echo "==> Installing VS Code extensions in WSL"
if command -v code &>/dev/null; then
  while IFS= read -r ext; do
    ext=$(echo "$ext" | xargs)
    if [ -n "$ext" ] && [[ ! "$ext" =~ ^# ]]; then
      echo "    Installing $ext"
      code --install-extension "$ext" --force
    fi
  done < "$REPO_ROOT/vscode/extensions.txt"
else
  echo "    VS Code 'code' CLI not available in WSL yet. Extensions will install on first Remote-WSL connect."
fi

echo "==> Done."
