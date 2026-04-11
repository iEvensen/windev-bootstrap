# windev-bootstrap

Bootstrap a Windows + WSL2 (Ubuntu) development environment with:

- Docker inside WSL with custom networking
- k3d Kubernetes cluster (declarative config)
- VS Code Dev Containers (per-project tooling)
- zsh + Oh My Zsh (inside containers)
- Git + GitHub CLI + HTTPS authentication (SSH optional)
- Shared VS Code settings and extensions across host, WSL, and dev containers

## Prerequisites

- Windows with WSL feature enabled (`wsl --install --no-distribution`)
- A GitHub Personal Access Token with these scopes:
  - `repo` — required for `gh` operations
  - `read:org` — required by `gh auth login`
  - `admin:public_key` — only needed if you opt into SSH setup

## Architecture

WSL Ubuntu stays thin — just Docker + k3d. All dev tooling lives in Dev Containers:

```
Windows (host)
├── VS Code + Remote-WSL extension
├── Windows Terminal (Dracula + JetBrainsMono)
├── Git, GitHub CLI (via winget)
└── WSL2 Ubuntu
    ├── Docker engine
    ├── k3d cluster
    ├── SSH keys (optional, generated if SSH setup is chosen)
    ├── Git config (symlinked from dotfiles/)
    ├── VS Code Server (settings + extensions from vscode/)
    └── Dev Containers (per project)
        ├── zsh + Oh My Zsh + plugins
        ├── kubectl, helm
        ├── Language tooling (.NET / Node / etc.)
        └── VS Code extensions (inherits WSL settings + container-specific)
```

### VS Code Settings Inheritance

```
vscode/settings.json (single source of truth)
├── Windows host  →  merged into %APPDATA%\Code\User\settings.json
├── WSL distro    →  copied to ~/.vscode-server/data/Machine/settings.json
└── Dev containers →  inherited from WSL user settings automatically
                      devcontainer.json only adds container-specific extensions
```

## Structure

```
windev-bootstrap/
  windows/
    install.ps1              # Windows bootstrap — runs everything from one script
    .wslconfig               # WSL2 resource & networking config
    winget-packages.json     # Windows packages (Terminal, VS Code, Git, gh CLI)
    vscode-settings.json     # Windows-side VS Code settings (merged, not overwritten)
    terminal-settings.json   # Windows Terminal settings (Dracula + JetBrainsMono)
  wsl/
    install.sh               # WSL entry point (apt base packages → ubuntu-setup.sh)
    ubuntu-setup.sh          # Docker, k3d, kubectl, dotfiles, VS Code settings/extensions
    wsl.conf                 # WSL config template (systemd, default user — written to /etc/wsl.conf)
    docker/
      daemon.json            # Custom Docker networking
      network-setup.sh       # Restart Docker & verify
    k3d/
      k3d-dev.yaml           # Declarative k3d cluster config
      create-cluster.sh      # Create cluster from config
  github/
    setup-github.sh          # GitHub CLI + auth (PAT or interactive) + optional SSH key
  devcontainer/
    Dockerfile.base          # Base dev container (zsh, kubectl, helm)
    zsh/
      .zshrc                 # Shared zsh config
      .aliases               # Shared shell aliases
    examples/
      dotnet/.devcontainer/  # .NET dev container template
      typescript/.devcontainer/  # TypeScript dev container template
  vscode/
    settings.json            # Base VS Code settings (applied to WSL + inherited by containers)
    extensions.txt           # VS Code extensions (installed in WSL)
  dotfiles/
    .gitconfig               # Git config (identity, rebase)
    .gitignore_global        # Global gitignore
```

## Usage

### 1. Before you start

1. Edit `dotfiles/.gitconfig` — set your `name` and `email` under `[user]`
2. Ensure WSL is installed: `wsl --install --no-distribution` (reboot if needed)
3. Have a GitHub PAT ready

### 2. Run the bootstrap

```powershell
git clone https://github.com/iEvensen/windev-bootstrap.git
cd windev-bootstrap\windows
.\install.ps1
```

The script will prompt for:
- **WSL username** and **password**
- **GitHub Personal Access Token**
- **SSH setup** (optional, default: no — HTTPS is used)

Then it automatically:
1. Applies `.wslconfig` to the Windows host
2. Installs the Ubuntu distro (no launch)
3. Creates WSL user and writes `wsl.conf` (systemd + default user)
4. Restarts the distro so `wsl.conf` takes effect
5. Installs Windows packages via winget (Terminal, VS Code, Git, gh)
6. Installs the VS Code Remote-WSL extension on the host
7. Merges `vscode-settings.json` into Windows VS Code settings
8. Applies Windows Terminal settings
9. Copies the repo into WSL, fixes ownership, makes scripts executable
10. Shuts down WSL so systemd boots as PID 1
11. Runs WSL setup: apt packages, Docker, k3d cluster, kubectl, dotfiles, VS Code settings/extensions
12. Runs GitHub setup (gh auth with PAT, credential helper; SSH key generation if opted in)

### 3. Use Dev Containers in your projects

Copy a template into your project:

```bash
# For a .NET project
cp -r ~/windev-bootstrap/devcontainer/examples/dotnet/.devcontainer/ ~/projects/my-dotnet-api/

# For a TypeScript project
cp -r ~/windev-bootstrap/devcontainer/examples/typescript/.devcontainer/ ~/projects/my-ts-app/
```

Then in VS Code: open the project folder and select **"Reopen in Container"**.

Each container gets:
- zsh + Oh My Zsh + all plugins
- kubectl + helm (connected to k3d cluster on host)
- Docker CLI (via Docker socket mount)
- Language-specific tooling and VS Code extensions
- VS Code settings inherited from WSL

## Configuration

### WSL2 Resources

| Setting | Value | Purpose |
|---------|-------|---------|
| memory | 12GB | Caps WSL RAM usage |
| swap | 12GB | Prevents OOM kills |
| processors | 8 | Enough for parallel builds |
| networkingMode | mirrored | Best for Docker + k3d |
| dnsTunneling | true | Fixes Docker DNS issues |
| autoMemoryReclaim | gradual | Prevents memory ballooning |

### Docker Networking

- Bridge IP: `192.168.1.1/24`
- Default address pool: `192.168.4.0/22` (size /24)

### k3d Cluster

- Image: `rancher/k3s:v1.35.3-k3s1`
- 1 server + 2 agents
- Traefik disabled (bring your own ingress)
- Port 8080 mapped to load balancer (HTTP)
- Port 8443 mapped to load balancer (HTTPS)
- API on port 6550
- Persistent storage at `/var/lib/k3d/dev`

### Git

- `pull.rebase = true` — clean linear history by default
- HTTPS is the default protocol for GitHub (via `gh` credential helper)
- SSH is available as an opt-in (`--ssh` flag or `SETUP_SSH=true`)
- Identity (name/email) configured in `dotfiles/.gitconfig`
