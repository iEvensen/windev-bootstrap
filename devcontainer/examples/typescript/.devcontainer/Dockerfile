FROM mcr.microsoft.com/devcontainers/typescript-node:24

ARG USERNAME=node
USER $USERNAME

# Install fzf
RUN sudo apt-get update && sudo apt-get install -y fzf && sudo rm -rf /var/lib/apt/lists/*

# Oh My Zsh plugins (OMZ is pre-installed in Microsoft base images)
RUN git clone https://github.com/zsh-users/zsh-autosuggestions \
      ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions \
    && git clone https://github.com/zsh-users/zsh-syntax-highlighting.git \
       ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting \
    && git clone https://github.com/zdharma-continuum/fast-syntax-highlighting.git \
       ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/fast-syntax-highlighting \
    && git clone https://github.com/zsh-users/zsh-history-substring-search.git \
       ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-history-substring-search

COPY --chown=$USERNAME:$USERNAME .zshrc /home/$USERNAME/.zshrc
COPY --chown=$USERNAME:$USERNAME .aliases /home/$USERNAME/.aliases
