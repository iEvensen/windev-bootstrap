Param(
    [string]$DistroName = "Ubuntu"
)

$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as Administrator to install packages and configure WSL. Please restart PowerShell as Admin."
    exit 1
}

# Resolve the invoking user's profile paths (correct even when elevated via runas)
$OriginalUserProfile = (Get-CimInstance Win32_UserProfile | Where-Object {
    $_.SID -eq ([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
}).LocalPath
$OriginalAppData = "$OriginalUserProfile\AppData\Roaming"
$OriginalLocalAppData = "$OriginalUserProfile\AppData\Local"

# Verify WSL is available
if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) {
    Write-Error "WSL is not installed. Please install WSL first: wsl --install --no-distribution"
    exit 1
}

# --- Prompts ---
$WSL_USER = Read-Host "Enter desired WSL username"
if ($WSL_USER -notmatch '^[a-z_][a-z0-9_-]*$') {
    Write-Error "Invalid username. Use only lowercase letters, digits, underscores, and hyphens."
    exit 1
}
$WSL_PASS = Read-Host "Enter desired WSL password" -AsSecureString
$GH_PAT = Read-Host "Enter your GitHub Personal Access Token" -AsSecureString

$SetupSSH = Read-Host "Set up SSH for GitHub? HTTPS is used by default (y/N)"
if ($SetupSSH -match '^[Yy]') {
    $env:SETUP_SSH = "true"
} else {
    $env:SETUP_SSH = "false"
}

# Convert secure strings and release BSTRs
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($WSL_PASS)
$PlainPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)

$BSTR_GH = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($GH_PAT)
$PlainToken = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR_GH)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR_GH)

# Set env vars for WSLENV passthrough into WSL
$env:WSL_USER = $WSL_USER
$env:WSL_PASS = $PlainPass
$env:GH_PAT = $PlainToken
$env:WSLENV = "WSL_USER/u:WSL_PASS/u:GH_PAT/u:SETUP_SSH/u"

# --- .wslconfig ---
Write-Host "`n==> Applying .wslconfig"
Copy-Item -Path ".\.wslconfig" -Destination "$OriginalUserProfile\.wslconfig" -Force

# --- Install distro (WSL feature must already be installed) ---
Write-Host "`n==> Installing $DistroName distro"
wsl --install -d $DistroName --no-launch
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to install $DistroName distro."; exit 1 }

# --- Create WSL user ---
Write-Host "`n==> Initializing WSL user..."
wsl -d $DistroName -u root -- useradd -m -G sudo -s /bin/bash $WSL_USER
wsl -d $DistroName -u root -- bash -c "echo '${WSL_USER}:${PlainPass}' | chpasswd"
wsl -d $DistroName -u root -- bash -c "echo '${WSL_USER} ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/${WSL_USER} && chmod 440 /etc/sudoers.d/${WSL_USER}"
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to create WSL user."; exit 1 }
$repoRoot = Split-Path -Parent $PSScriptRoot
$wslConf = (Get-Content "$repoRoot\wsl\wsl.conf" -Raw) -replace 'WSLUSERPLACEHOLDER', $WSL_USER
$wslConf | wsl -d $DistroName -u root tee /etc/wsl.conf > $null
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to write wsl.conf."; exit 1 }

# Restart distro so wsl.conf (default user + systemd) takes effect
wsl --terminate $DistroName

# --- Winget packages ---
Write-Host "`n==> Installing packages via winget"
winget import .\winget-packages.json --accept-package-agreements --accept-source-agreements --disable-interactivity --no-upgrade

# --- VS Code Remote-WSL extension (other extensions install inside WSL) ---
Write-Host "`n==> Installing VS Code Remote-WSL extension"
code --install-extension ms-vscode-remote.remote-wsl --force

# --- VS Code Windows settings ---
Write-Host "`n==> Applying VS Code Windows settings"
$vscodeSettingsDir = "$OriginalAppData\Code\User"
$vscodeSettingsFile = "$vscodeSettingsDir\settings.json"
if (Test-Path $vscodeSettingsDir) {
    $newSettings = Get-Content ".\vscode-settings.json" -Raw | ConvertFrom-Json
    if (Test-Path $vscodeSettingsFile) {
        $existing = Get-Content $vscodeSettingsFile -Raw | ConvertFrom-Json
    } else {
        $existing = New-Object PSObject
    }
    foreach ($prop in $newSettings.PSObject.Properties) {
        $existing | Add-Member -MemberType NoteProperty -Name $prop.Name -Value $prop.Value -Force
    }
    $existing | ConvertTo-Json -Depth 10 | Set-Content $vscodeSettingsFile -Encoding UTF8
    Write-Host "    VS Code settings merged."
} else {
    Write-Host "    VS Code settings directory not found. Open VS Code once, then re-run this step."
}

# --- Windows Terminal settings ---
Write-Host "`n==> Applying Windows Terminal settings"
$terminalSettingsPath = "$OriginalLocalAppData\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
if (Test-Path (Split-Path $terminalSettingsPath)) {
    Copy-Item -Path ".\terminal-settings.json" -Destination $terminalSettingsPath -Force
    Write-Host "    Windows Terminal settings applied."
} else {
    Write-Host "    Windows Terminal not found. It will be installed by winget; re-run to apply settings."
}

# --- Copy repo into WSL ---
Write-Host "`n==> Copying repo into WSL"
$repoRoot = Split-Path -Parent $PSScriptRoot
$wslHome = $null
$wslDest = $null

# Ensure distro is running before accessing UNC path
Write-Host "    Starting WSL distro..."
wsl -d $DistroName -- echo "WSL is ready"

# Try both UNC paths (\\wsl.localhost\ is preferred on newer Windows builds)
foreach ($uncRoot in @("\\wsl.localhost", "\\wsl$")) {
    $candidate = "$uncRoot\$DistroName\home\$WSL_USER"
    if (Test-Path $candidate) {
        $wslHome = $candidate
        $wslDest = "$wslHome\windev-bootstrap"
        break
    }
}

if (-not $wslHome) {
    Write-Error "WSL home directory not found. Ensure the distro is installed and the user '$WSL_USER' exists."
    exit 1
}

if (Test-Path $wslHome) {
    if (Test-Path $wslDest) {
        Write-Host "    Repo already exists in WSL at ~/windev-bootstrap, skipping copy."
    } else {
        Copy-Item -Path $repoRoot -Destination $wslDest -Recurse -Force
        Write-Host "    Repo copied to WSL at ~/windev-bootstrap"
    }

    # Fix ownership (Copy-Item via UNC creates files owned by root)
    Write-Host "`n==> Fixing file ownership in WSL"
    wsl -d $DistroName -u root bash -c 'chown -R "$WSL_USER:$WSL_USER" "/home/$WSL_USER/windev-bootstrap"'
    if ($LASTEXITCODE -ne 0) { Write-Error "Failed to fix file ownership."; exit 1 }

    # Make scripts executable
    wsl -d $DistroName -u $WSL_USER bash -c 'chmod +x ~/windev-bootstrap/wsl/install.sh ~/windev-bootstrap/wsl/ubuntu-setup.sh ~/windev-bootstrap/github/setup-github.sh ~/windev-bootstrap/wsl/k3d/create-cluster.sh ~/windev-bootstrap/wsl/docker/network-setup.sh'
    if ($LASTEXITCODE -ne 0) { Write-Error "Failed to make scripts executable."; exit 1 }

    # Shutdown WSL so systemd boots as PID 1 on next launch
    Write-Host "`n==> Restarting WSL for systemd..."
    wsl --shutdown

    # Run WSL setup (apt packages, docker, k3d, kubectl, dotfiles, git config)
    Write-Host "`n==> Running WSL setup scripts..."
    wsl -d $DistroName -u $WSL_USER bash -c 'cd ~/windev-bootstrap && ./wsl/install.sh'
    if ($LASTEXITCODE -ne 0) { Write-Error "WSL setup failed."; exit 1 }

    # Run GitHub setup (gh CLI, auth with PAT, SSH key)
    Write-Host "`n==> Running GitHub setup..."
    wsl -d $DistroName -u $WSL_USER bash -c 'cd ~/windev-bootstrap && ./github/setup-github.sh'
    if ($LASTEXITCODE -ne 0) { Write-Error "GitHub setup failed."; exit 1 }
}

# --- Cleanup ---
Write-Host "`n==> Cleaning up credentials from environment"
$PlainPass = $null
$PlainToken = $null
$env:WSL_USER = $null
$env:WSL_PASS = $null
$env:GH_PAT = $null
$env:SETUP_SSH = $null
$env:WSLENV = $null

Write-Host "`n==> Setup complete! Restart Windows Terminal to apply all settings."
