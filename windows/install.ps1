Param(
    [string]$DistroName = "Ubuntu"
)

Write-Host "==> Applying .wslconfig"
Copy-Item -Path ".\.wslconfig" -Destination "$env:USERPROFILE\.wslconfig" -Force

Write-Host "==> Installing WSL and Ubuntu"
wsl --install -d $DistroName

Write-Host "==> Installing packages via winget"
winget import .\winget-packages.json --accept-package-agreements --accept-source-agreements

Write-Host "==> VS Code WSL extension"
code --install-extension ms-vscode-remote.remote-wsl

Write-Host "==> Applying Windows Terminal settings"
$terminalSettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
if (Test-Path (Split-Path $terminalSettingsPath)) {
    Copy-Item -Path ".\terminal-settings.json" -Destination $terminalSettingsPath -Force
    Write-Host "    Windows Terminal settings applied."
} else {
    Write-Host "    Windows Terminal not found. Install it first, then re-run."
}

Write-Host "==> Done. Restart your machine if WSL was just installed."
