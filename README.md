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

Optional unattended toggle:

- Set `INSTALL_PORTAINER=true` before running `windows/install.ps1` to install Portainer during bootstrap.
- If not set, Portainer remains an opt-in manual step.

Example:

```powershell
$env:INSTALL_PORTAINER = "true"
cd windev-bootstrap\windows
.\install.ps1
```

### 3. Optional: Rider/Testcontainers without Docker Desktop

If you want Rider on Windows to connect to Docker Engine running inside WSL, use the optional helper script:

```bash
cd ~/windev-bootstrap
chmod +x wsl/docker/enable-rider-remote-daemon.sh
./wsl/docker/enable-rider-remote-daemon.sh
```

To disable this and restore default Docker service behavior:

```bash
./wsl/docker/disable-rider-remote-daemon.sh
```

The script configures Docker to listen on TCP port `2375` in addition to the Unix socket, without overwriting existing Docker network settings in `daemon.json`.

Default behavior is security-first:

- Binds to `127.0.0.1` by default
- For non-loopback binds, applies an `iptables` source restriction when possible

Security note:

- Port `2375` is unauthenticated and unencrypted (no TLS)
- Use this only for local development on trusted networks
- To bind to a specific non-loopback address and restrict source to your Windows host, run:

```bash
./wsl/docker/enable-rider-remote-daemon.sh --bind <wsl-ip> --allow-from <windows-ip>
```

- To bind on all interfaces (least secure), run:

```bash
./wsl/docker/enable-rider-remote-daemon.sh --bind-all --allow-insecure-public-bind
```

### 4. Optional: Portainer (Docker GUI)

Install Portainer for the local Docker Engine in WSL:

```bash
cd ~/windev-bootstrap
./wsl/docker/install-portainer.sh
```

Open Portainer at:

```text
https://localhost:9443
```

Notes:

- Uses `9443` intentionally because `9000` is already used by k3d/Traefik in this setup
- Binds to `127.0.0.1` only (not exposed on your LAN)

Optional: allow Portainer to manage the local k3d cluster too:

```bash
./wsl/docker/prepare-portainer-k3d-access.sh
```

Then import the generated kubeconfig file in Portainer's Kubernetes environment wizard.

### 5. Use Dev Containers

Copy a template into your project:

```bash
cp -r ~/windev-bootstrap/devcontainer/examples/typescript/.devcontainer/ ~/projects/workspace/my-app/
```

Then open the folder in VS Code and select **"Reopen in Container"**.

## Structure

```text
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
      enable-rider-remote-daemon.sh # Optional Rider/Testcontainers TCP endpoint helper
      disable-rider-remote-daemon.sh # Optional helper to revert Rider/Testcontainers TCP endpoint
      install-portainer.sh   # Optional Portainer CE install/start (Docker GUI)
      prepare-portainer-k3d-access.sh # Optional kubeconfig generator for Portainer -> k3d
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

```text
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
