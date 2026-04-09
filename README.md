# windev-bootstrap

Bootstrap a Windows + WSL2 (Ubuntu) development environment with:

- zsh + Oh My Zsh
- Docker inside WSL with custom networking
- k3d Kubernetes cluster (declarative config)
- VS Code configuration
- Git + GitHub CLI + SSH

## Structure

```
windev-bootstrap/
  windows/
    install.ps1            # Windows bootstrap (WSL, winget, VS Code, Terminal)
    .wslconfig             # WSL2 resource & networking config
    winget-packages.json   # Windows packages to install
    vscode-settings.json   # Windows-side VS Code settings
    terminal-settings.json # Windows Terminal settings (Dracula + JetBrainsMono)
  wsl/
    install.sh           # WSL entry point
    ubuntu-setup.sh      # Docker, k3d, kubectl, zsh, dotfiles
    zsh/
      install-zsh.sh     # Oh My Zsh + plugins
      .zshrc             # zsh config
      .aliases           # Shell aliases
    docker/
      daemon.json        # Custom Docker networking
      network-setup.sh   # Restart Docker & verify
    k3d/
      k3d-dev.yaml       # Declarative k3d cluster config
      create-cluster.sh  # Create cluster from config
  github/
    setup-github.sh      # GitHub CLI + SSH key setup
  vscode/
    settings.json        # WSL-side VS Code settings
    extensions.txt       # VS Code extensions to install
  dotfiles/
    .gitconfig           # Git config template
    .gitignore_global    # Global gitignore
```

## Usage

### 1. On Windows

```powershell
git clone https://github.com/iEvensen/windev-bootstrap.git
cd windev-bootstrap\windows
.\install.ps1
```

Restart your machine if WSL was just installed.

### 2. Inside WSL (Ubuntu)

```bash
cd ~/windev-bootstrap/wsl
./install.sh
```

### 3. Set up GitHub

```bash
cd ~/windev-bootstrap/github
./setup-github.sh
```

### 4. Create k3d cluster

```bash
cd ~/windev-bootstrap/wsl/k3d
./create-cluster.sh
```

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
- Port 8080 mapped to load balancer
- API on port 6550
- Persistent storage enabled
