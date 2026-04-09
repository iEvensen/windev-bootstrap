export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="agnoster"

plugins=(
  git
  kubectl
  docker
  zsh-autosuggestions
  zsh-syntax-highlighting
)

source $ZSH/oh-my-zsh.sh

[ -f "$HOME/.aliases" ] && source "$HOME/.aliases"

export EDITOR="code"
export KUBECONFIG="$HOME/.kube/config"
