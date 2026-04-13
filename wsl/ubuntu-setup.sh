#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$HOME/windev-bootstrap}"

echo "==> Docker: adding official Docker APT repository"
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update

echo "==> Docker: installing engine"
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

echo "==> Adding user to docker group"
sudo usermod -aG docker "$USER"

echo "==> Configuring Docker daemon"
sudo mkdir -p /etc/docker
sudo cp "$REPO_ROOT/wsl/docker/daemon.json" /etc/docker/daemon.json

echo "==> Starting Docker"
if [ "$(ps -p 1 -o comm=)" = "systemd" ]; then
  sudo systemctl enable docker
  sudo systemctl restart docker
else
  echo "    systemd not running as PID 1; starting dockerd directly..."
  sudo dockerd &>/dev/null &
fi
echo "    Waiting for Docker daemon..."
for i in $(seq 1 30); do
  sudo docker info &>/dev/null && break
  sleep 1
done
sudo docker info &>/dev/null || { echo "ERROR: Docker daemon failed to start"; sudo journalctl -u docker --no-pager -n 30 2>/dev/null; exit 1; }

echo "==> Installing k3d"
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

echo "==> Installing kubectl"
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/kubectl

echo "==> Creating k3d storage directory"
sudo mkdir -p /var/lib/k3d/dev

echo "==> Creating k3d cluster"
sg docker -c "bash \"$REPO_ROOT/wsl/k3d/create-cluster.sh\""

echo "==> Enabling k3d cluster auto-start on boot"
sudo cp "$REPO_ROOT/wsl/k3d/k3d-dev-cluster.service" /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable k3d-dev-cluster.service

echo "==> Creating project directories"
mkdir -p "$HOME/projects/workspace"

echo "==> Installing fzf"
sudo apt install -y fzf

echo "==> Installing zsh"
sudo apt install -y zsh
sudo chsh -s "$(which zsh)" "$USER"

echo "==> Installing oh-my-zsh"
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

echo "==> Installing zsh custom plugins"
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
declare -A custom_plugins=(
  [zsh-autosuggestions]=https://github.com/zsh-users/zsh-autosuggestions
  [zsh-syntax-highlighting]=https://github.com/zsh-users/zsh-syntax-highlighting
  [fast-syntax-highlighting]=https://github.com/zdharma-continuum/fast-syntax-highlighting
  [zsh-history-substring-search]=https://github.com/zsh-users/zsh-history-substring-search
)
for plugin in "${!custom_plugins[@]}"; do
  dest="$ZSH_CUSTOM/plugins/$plugin"
  if [ ! -d "$dest" ]; then
    echo "    Cloning $plugin"
    git clone --depth=1 "${custom_plugins[$plugin]}" "$dest"
  else
    echo "    $plugin already installed"
  fi
done

echo "==> Linking dotfiles"
ln -sf "$REPO_ROOT/dotfiles/.gitconfig" "$HOME/.gitconfig"
ln -sf "$REPO_ROOT/dotfiles/.gitignore_global" "$HOME/.gitignore_global"
ln -sf "$REPO_ROOT/devcontainer/zsh/.zshrc" "$HOME/.zshrc"
ln -sf "$REPO_ROOT/devcontainer/zsh/.aliases" "$HOME/.aliases"

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
