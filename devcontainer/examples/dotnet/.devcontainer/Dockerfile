FROM mcr.microsoft.com/devcontainers/dotnet:10.0

ARG USERNAME=vscode
USER $USERNAME

# Install fzf
RUN sudo apt-get -o Acquire::Retries=3 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 -o APT::Update::Error-Mode=any update \
    && sudo apt-get -o Acquire::Retries=3 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 install -y fzf \
    && sudo rm -rf /var/lib/apt/lists/*

# Oh My Zsh plugins (OMZ is pre-installed in Microsoft base images)
RUN retry_clone() { \
      attempt=1; \
      while ! git clone "$@"; do \
        if [ "$attempt" -ge 4 ]; then return 1; fi; \
        printf 'Git clone failed; retrying (%s/3)...\n' "$attempt" >&2; \
        attempt=$((attempt + 1)); \
        sleep 2; \
      done; \
    }; \
    retry_clone https://github.com/zsh-users/zsh-autosuggestions \
      ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions \
    && retry_clone https://github.com/zsh-users/zsh-syntax-highlighting.git \
       ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting \
    && retry_clone https://github.com/zdharma-continuum/fast-syntax-highlighting.git \
       ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/fast-syntax-highlighting \
    && retry_clone https://github.com/zsh-users/zsh-history-substring-search.git \
       ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-history-substring-search

COPY --chown=$USERNAME:$USERNAME .zshrc /home/$USERNAME/.zshrc
COPY --chown=$USERNAME:$USERNAME .aliases /home/$USERNAME/.aliases
