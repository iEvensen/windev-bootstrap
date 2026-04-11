$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as Administrator to install packages and configure WSL. Please restart PowerShell as Admin."
    exit
}

Param(
    [string]$DistroName = "Ubuntu"
)

$WSL_USER = Read-Host "Enter desired WSL username"
$WSL_PASS = Read-Host "Enter desired WSL password" -AsSecureString
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($WSL_PASS)
$PlainPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

$env:WSL_USER = $WSL_USER
$env:WSL_PASS = $PlainPass
$env:WSLENV = "WSL_USER/u:WSL_PASS/u"

Write-Host "==> Applying .wslconfig"
Copy-Item -Path ".\.wslconfig" -Destination "$env:USERPROFILE\.wslconfig" -Force

Write-Host "==> Installing WSL and Ubuntu"
wsl --install -d $DistroName --no-launch

Write-Host "==> Initializing WSL user..."
wsl -d $DistroName -u root bash -c "useradd -m -G sudo -s /bin/bash ${WSL_USER} && echo '${WSL_USER}:${PlainPass}' | chpasswd"

wsl -d $DistroName -u root bash -c "echo -e '[user]\ndefault=$WSL_USER' > /etc/wsl.conf"

Write-Host "==> Installing packages via winget"
winget import .\winget-packages.json --accept-package-agreements --accept-source-agreements --silent --force

Write-Host "==> VS Code WSL extension"
code --install-extension ms-vscode-remote.remote-wsl --force

Write-Host "==> Applying Windows Terminal settings"
$terminalSettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
if (Test-Path (Split-Path $terminalSettingsPath)) {
    Copy-Item -Path ".\terminal-settings.json" -Destination $terminalSettingsPath -Force
    Write-Host "    Windows Terminal settings applied."
} else {
    Write-Host "    Windows Terminal not found. Install it first, then re-run."
}

Write-Host "==> Copying repo into WSL"
$repoRoot = Split-Path -Parent $PSScriptRoot
$wslHome = "\\wsl$\$DistroName\home\$WSL_USER"
$wslDest = "$wslHome\windev-bootstrap"

Start-Sleep -Seconds 3

if (Test-Path $wslHome) {
    if (Test-Path $wslDest) {
        Write-Host "    Repo already exists in WSL at ~/windev-bootstrap, skipping copy."
    } else {
        Copy-Item -Path $repoRoot -Destination $wslDest -Recurse -Force
        Write-Host "    Repo copied to WSL at ~/windev-bootstrap"
    }
    Write-Host ""
    Write-Host "==> Next steps inside WSL:"
    Write-Host "    cd ~/windev-bootstrap/wsl && ./install.sh"
    Write-Host "    cd ~/windev-bootstrap/github && ./setup-github.sh"
} else {
    Write-Host "    WSL home directory not found. You may need to restart and launch Ubuntu first."
    Write-Host "    Then manually copy or clone the repo into WSL."
}

Write-Host "==> Done. Restart your machine if WSL was just installed."
