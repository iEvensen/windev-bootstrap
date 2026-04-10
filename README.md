# windev-bootstrap

Bootstrap a Windows + WSL2 (Ubuntu) development environment with:

- Docker inside WSL with custom networking
- k3d Kubernetes cluster (declarative config)
- VS Code Dev Containers (per-project tooling)
- zsh + Oh My Zsh (inside containers)
- Git + GitHub CLI + SSH/HTTPS authentication

## Architecture

WSL Ubuntu stays thin — just Docker + k3d. All dev tooling lives in Dev Containers:

```
Windows
└── WSL2 Ubuntu (host)
    ├── Docker engine
    ├── k3d cluster
    ├── SSH keys + git config
    └── Dev Containers (per project)
        ├── zsh + Oh My Zsh + plugins
        ├── kubectl, helm
        ├── Language tooling (.NET / Node / etc.)
        └── VS Code extensions
```

## Structure

```
windev-bootstrap/
  windows/
    install.ps1              # Windows bootstrap (WSL, winget, VS Code, Terminal)
    .wslconfig               # WSL2 resource & networking config
    winget-packages.json     # Windows packages to install
    vscode-settings.json     # Windows-side VS Code settings
    terminal-settings.json   # Windows Terminal settings (Dracula + JetBrainsMono)
  wsl/
    install.sh               # WSL entry point (Docker + k3d only)
    ubuntu-setup.sh          # Docker engine, k3d, kubectl, git config
    docker/
      daemon.json            # Custom Docker networking
      network-setup.sh       # Restart Docker & verify
    k3d/
      k3d-dev.yaml           # Declarative k3d cluster config
      create-cluster.sh      # Create cluster from config
  github/
    setup-github.sh          # GitHub CLI + SSH key + credential helper
  devcontainer/
    Dockerfile.base          # Base dev container (zsh, kubectl, helm)
    zsh/
      .zshrc                 # Shared zsh config
      .aliases               # Shared shell aliases
    examples/
      dotnet/.devcontainer/  # .NET dev container template
      typescript/.devcontainer/  # TypeScript dev container template
  vscode/
    settings.json            # VS Code settings reference
    extensions.txt           # VS Code extensions reference
  dotfiles/
    .gitconfig               # Git config (rebase, SSH default)
    .gitignore_global        # Global gitignore
```

## Usage

### 1. On Windows

```powershell
git clone https://github.com/iEvensen/windev-bootstrap.git
cd windev-bootstrap\windows
.\install.ps1
```

This will install WSL + Ubuntu, apply configs, and **copy the repo into WSL** automatically.
Restart your machine if WSL was just installed.

### 2. Inside WSL (Ubuntu)

```bash
cd ~/windev-bootstrap/wsl
./install.sh
```

### 3. Set up GitHub

Authenticate via browser, SSH key, or PAT — the script handles all three:

```bash
cd ~/windev-bootstrap/github
./setup-github.sh
```

### 4. Create k3d cluster

```bash
cd ~/windev-bootstrap/wsl/k3d
./create-cluster.sh
```

### 5. Use Dev Containers in your projects

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

## Configuration

### WSL2 Resources (32GB RAM machine)

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

- 1 server + 2 agents
- Traefik disabled (bring your own ingress)
- Port 8080 mapped to load balancer (HTTP)
- Port 8443 mapped to load balancer (HTTPS)
- API on port 6550
- Persistent storage enabled

### Git

- `pull.rebase = true` — clean linear history by default
- HTTPS URLs for GitHub automatically rewritten to SSH
- `gh` registered as git credential helper (HTTPS fallback)
- Identity (name/email) prompted at setup time — not stored in repo
