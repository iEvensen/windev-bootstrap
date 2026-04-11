export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="agnoster"

HISTSIZE=100000
SAVEHIST=100000
HISTFILE="$HOME/.zsh_history"
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt SHARE_HISTORY

plugins=(
  git
  kubectl
  docker
  npm
  node
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
