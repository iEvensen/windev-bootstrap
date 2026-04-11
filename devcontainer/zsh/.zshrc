export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="agnoster"

HISTSIZE=100000
SAVEHIST=100000
HISTFILE="$HOME/.zsh_history"
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt SHARE_HISTORY

ZSH_CUSTOM="${ZSH_CUSTOM:-$ZSH/custom}"

# Custom plugins – cloned automatically if missing
typeset -A custom_plugins=(
  [zsh-autosuggestions]=https://github.com/zsh-users/zsh-autosuggestions
  [zsh-syntax-highlighting]=https://github.com/zsh-users/zsh-syntax-highlighting
  [fast-syntax-highlighting]=https://github.com/zdharma-continuum/fast-syntax-highlighting
  [zsh-history-substring-search]=https://github.com/zsh-users/zsh-history-substring-search
)

for plugin repo in "${(@kv)custom_plugins}"; do
  if [[ ! -d "$ZSH_CUSTOM/plugins/$plugin" ]]; then
    git clone --depth=1 "$repo" "$ZSH_CUSTOM/plugins/$plugin" 2>/dev/null
  fi
done
unset custom_plugins

plugins=(
  git
  kubectl
  docker
  zsh-autosuggestions
  zsh-syntax-highlighting
  fast-syntax-highlighting
  fzf
  zsh-interactive-cd
  zsh-history-substring-search
)

source $ZSH/oh-my-zsh.sh

[ -f "$HOME/.aliases" ] && source "$HOME/.aliases"

export EDITOR="code"
export KUBECONFIG="$HOME/.kube/config"
