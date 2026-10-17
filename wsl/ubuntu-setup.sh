#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$HOME/windev-bootstrap}"
source "$REPO_ROOT/lib/network.sh"

echo "==> Docker: adding official Docker APT repository"
sudo install -m 0755 -d /etc/apt/keyrings
download https://download.docker.com/linux/ubuntu/gpg | \
  gpg --dearmor | sudo tee /etc/apt/keyrings/docker.gpg > /dev/null
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
apt_get update

echo "==> Docker: installing engine"
apt_get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin util-linux-extra

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
for _ in $(seq 1 30); do
  sudo docker info &>/dev/null && break
  sleep 1
done
sudo docker info &>/dev/null || { echo "ERROR: Docker daemon failed to start"; sudo journalctl -u docker --no-pager -n 30 2>/dev/null; exit 1; }

echo "==> Installing k3d"
download https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

echo "==> Installing kubectl"
KUBECTL_VERSION="$(download https://dl.k8s.io/release/stable.txt)"
download "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" kubectl
chmod 0755 kubectl
sudo mv kubectl /usr/local/bin/kubectl

echo "==> Creating k3d storage directory"
sudo mkdir -p /var/lib/k3d/dev

echo "==> Creating k3d cluster"
sg docker -c "bash \"$REPO_ROOT/wsl/k3d/create-cluster.sh\""

echo "==> Enabling k3d cluster auto-start on boot"
sudo cp "$REPO_ROOT/wsl/k3d/k3d-dev-cluster.service" /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable k3d-dev-cluster.service

echo "==> Creating projects directory"
mkdir -p "$HOME/projects/workspace"

echo "==> Installing jq"
if ! command -v jq &>/dev/null; then
  apt_get install -y jq
else
  echo "    jq already installed"
fi

echo "==> Installing tree"
if ! command -v tree &>/dev/null; then
  apt_get install -y tree
else
  echo "    tree already installed"
fi

echo "==> Installing Helm"
if ! command -v helm &>/dev/null; then
  download https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | sudo bash
else
  echo "    helm already installed"
fi

echo "==> Installing Azure CLI"
if ! command -v az &>/dev/null; then
  sudo mkdir -p /etc/apt/keyrings
  download https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /etc/apt/keyrings/azure-cli.gpg > /dev/null
  sudo chmod a+r /etc/apt/keyrings/azure-cli.gpg
  AZ_REPO="$(lsb_release -cs)"
  echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/azure-cli.gpg] https://packages.microsoft.com/repos/azure-cli/ ${AZ_REPO} main" | \
    sudo tee /etc/apt/sources.list.d/azure-cli.list > /dev/null
  apt_get update
  apt_get install -y --no-install-recommends azure-cli
else
  echo "    Azure CLI already installed"
fi

echo "==> Installing Node.js via nvm"
if ! command -v nvm &>/dev/null && [ ! -d "$HOME/.nvm" ]; then
  download https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash
  export NVM_DIR="$HOME/.nvm"
  # shellcheck source=/dev/null
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  retry_download nvm install 25
else
  echo "    nvm already installed"
fi

echo "==> Installing .NET SDK"
if ! command -v dotnet &>/dev/null; then
  apt_get update
  apt_get install -y dotnet-sdk-10.0
else
  echo "    dotnet already installed"
fi

echo "==> Installing Pulumi"
if ! command -v pulumi &>/dev/null; then
  download https://get.pulumi.com | sh
  sudo ln -sf "$HOME/.pulumi/bin/pulumi" /usr/local/bin/pulumi
else
  echo "    pulumi already installed"
fi

echo "==> Installing HashiCorp Vault CLI"
if ! command -v vault &>/dev/null; then
  VAULT_VERSION="$(download https://checkpoint-api.hashicorp.com/v1/check/vault | jq -r '.current_version')"
  download "https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip" /tmp/vault.zip
  sudo unzip -o /tmp/vault.zip -d /usr/local/bin
  rm -f /tmp/vault.zip
else
  echo "    vault already installed"
fi

echo "==> Installing yq"
if ! command -v yq &>/dev/null; then
  YQ_VERSION="$(download https://api.github.com/repos/mikefarah/yq/releases/latest | jq -r '.tag_name')"
  download "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" /tmp/yq
  chmod +x /tmp/yq
  sudo install -m 0755 /tmp/yq /usr/local/bin/yq
  rm -f /tmp/yq
else
  echo "    yq already installed"
fi

echo "==> Installing k9s"
if ! command -v k9s &>/dev/null; then
  K9S_VERSION="$(download https://api.github.com/repos/derailed/k9s/releases/latest | jq -r '.tag_name')"
  download "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_amd64.tar.gz" /tmp/k9s.tar.gz
  tar -xzf /tmp/k9s.tar.gz -C /tmp k9s
  sudo install -m 0755 /tmp/k9s /usr/local/bin/k9s
  rm -f /tmp/k9s.tar.gz /tmp/k9s
else
  echo "    k9s already installed"
fi

echo "==> Installing fzf"
apt_get install -y fzf

echo "==> Installing zsh"
apt_get install -y zsh
sudo chsh -s "$(which zsh)" "$USER"

echo "==> Installing oh-my-zsh"
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  OMZ_INSTALLER="$(download https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  sh -c "$OMZ_INSTALLER" "" --unattended
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
    retry_download git clone --depth=1 "${custom_plugins[$plugin]}" "$dest"
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

if [[ "${INSTALL_PORTAINER:-false}" =~ ^([Tt][Rr][Uu][Ee]|[Yy]([Ee][Ss])?|1)$ ]]; then
  echo "==> INSTALL_PORTAINER is enabled, installing Portainer"
  bash "$REPO_ROOT/wsl/docker/install-portainer.sh"
else
  echo "==> INSTALL_PORTAINER is disabled, skipping Portainer install"
fi

echo "==> Installing VS Code extensions in WSL"
if command -v code &>/dev/null; then
  while IFS= read -r ext; do
    ext=$(echo "$ext" | xargs)
    if [ -n "$ext" ] && [[ ! "$ext" =~ ^# ]]; then
      echo "    Installing $ext"
      retry_download code --install-extension "$ext" --force
    fi
  done < "$REPO_ROOT/vscode/extensions.txt"
else
  echo "    VS Code 'code' CLI not available in WSL yet. Extensions will install on first Remote-WSL connect."
fi

echo "==> Done."
