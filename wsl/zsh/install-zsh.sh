#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$HOME/windev-bootstrap}"

echo "==> Installing Oh My Zsh"
export RUNZSH=no
export CHSH=no
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

echo "==> Installing plugins"
git clone https://github.com/zsh-users/zsh-autosuggestions \
  "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git \
  "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting"

echo "==> Linking .zshrc and aliases"
ln -sf "$REPO_ROOT/wsl/zsh/.zshrc" "$HOME/.zshrc"
ln -sf "$REPO_ROOT/wsl/zsh/.aliases" "$HOME/.aliases"
