# windev-bootstrap

Bootstrap a Windows + WSL2 (Ubuntu) development environment from a single script.

## What it sets up

**Windows**: VS Code, Windows Terminal, Git, GitHub CLI, JetBrainsMono Nerd Font

**WSL Ubuntu**: Docker, k3d cluster, Node.js (nvm), .NET SDK, Azure CLI, Helm, Pulumi, Vault CLI, kubectl, k9s, yq, jq, zsh + Oh My Zsh

**Dev Containers**: Per-project templates for .NET and TypeScript with shared zsh config

**Corporate network**: Automatic CA certificate export from Windows, HTTPS apt sources, SSL env vars for all tools

## Prerequisites

- Windows with WSL feature enabled (`wsl --install --no-distribution`)
- A GitHub Personal Access Token (`repo`, `read:org`, and `admin:public_key` if using SSH)

## Usage

### 1. Before you start

1. Edit `dotfiles/.gitconfig` — set your `name` and `email`
2. Ensure WSL is installed (reboot if needed)
3. Have a GitHub PAT ready

### 2. Run the bootstrap

```powershell
git clone https://github.com/iEvensen/windev-bootstrap.git
cd windev-bootstrap\windows
.\install.ps1
```

The script prompts for:
- WSL username and password
- GitHub Personal Access Token
- SSH setup (optional, default: HTTPS)
- Internal corporate registry (optional, default: Docker Hub)

Everything else is automatic.

### 3. Use Dev Containers

Copy a template into your project:

```bash
cp -r ~/windev-bootstrap/devcontainer/examples/typescript/.devcontainer/ ~/projects/workspace/my-app/
```

Then open the folder in VS Code and select **"Reopen in Container"**.

## Structure

```
windev-bootstrap/
  windows/
    install.ps1              # Main entry point — runs everything
    .wslconfig               # WSL2 resource & networking config
    winget-packages.json     # Windows packages
    vscode-settings.json     # Windows VS Code settings (merged, not overwritten)
    terminal-settings.json   # Windows Terminal settings
  wsl/
    install.sh               # WSL entry point (certs, apt, Microsoft repo → ubuntu-setup.sh)
    ubuntu-setup.sh          # Docker, k3d, all dev tools, zsh, dotfiles, VS Code extensions
    wsl.conf                 # WSL config (systemd, default user)
    docker/
      daemon.json            # Docker networking config
      network-setup.sh       # Restart Docker & verify
    k3d/
      k3d-dev.yaml           # Declarative k3d cluster config
      k3d-dev-cluster.service # Systemd service for auto-start on boot
      create-cluster.sh      # Create cluster from config
  github/
    setup-github.sh          # GitHub CLI auth + optional SSH key
  devcontainer/
    zsh/
      .zshrc                 # Shared zsh config (nvm, corp certs, oh-my-zsh)
      .aliases               # Shared shell aliases
    examples/
      dotnet/.devcontainer/  # .NET dev container template
      typescript/.devcontainer/  # TypeScript dev container template
  vscode/
    settings.json            # VS Code settings (applied to WSL, inherited by containers)
    extensions.txt           # VS Code extensions (installed in WSL)
  dotfiles/
    .gitconfig               # Git config (identity, rebase)
    .gitignore_global        # Global gitignore
```

## VS Code Settings Inheritance

```
vscode/settings.json (single source of truth)
├── Windows host   → merged into %APPDATA%\Code\User\settings.json
├── WSL distro     → copied to ~/.vscode-server/data/Machine/settings.json
└── Dev containers → inherited from WSL automatically
```

## Corporate SSL

When you select **internal corporate registry** during setup:

1. Non-public root CA certificates are exported from the Windows cert store (blocklist-filtered)
2. Certs are installed in WSL via `update-ca-certificates`
3. SSL environment variables are set for Node.js, Python, curl, Git, .NET, Azure CLI, and Pulumi
4. Env vars are persisted in `/etc/profile.d/corp-certs.sh` and sourced by `.zshrc`
5. Apt sources are switched to HTTPS (required for transparent TLS inspection)
6. Docker and k3d are configured to mirror Docker Hub via the internal registry

To manually add certificates, place `.crt` files in `certs/` before running setup.

## Idempotency

The script is safe to re-run at any time:

- Installs are skipped if already present (distro, packages, tools, fonts, plugins)
- Settings are merged, not overwritten (VS Code, Windows Terminal)
- Repo is always synced to WSL so changes are picked up
- GPG keyrings, apt sources, and k3d config are overwritten cleanly without prompts
