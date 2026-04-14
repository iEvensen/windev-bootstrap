#Requires -RunAsAdministrator
Param(
    [string]$DistroName = "Ubuntu"
)

Set-Variable -Name __PSLockdownPolicy -Value 0 -Scope Global -Force -ErrorAction SilentlyContinue
$ExecutionContext.SessionState.LanguageMode = "FullLanguage"

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

$UseInternal = Read-Host "Use internal corporate registry for container images? (y/N)"
$UseInternalRegistry = $UseInternal -match '^[Yy]'

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

# --- Export corporate CA bundle for Windows tools (Node.js, VS Code) ---
if ($UseInternalRegistry) {
    Write-Host "`n==> Exporting corporate CA bundle for Windows"
    $winCaBundlePath = "$env:TEMP\corp-ca-bundle.pem"
    $pemContent = ""
    Get-ChildItem -Path Cert:\LocalMachine\Root | Where-Object { $_.Subject -match "Helse|helsenord|HN-" } | ForEach-Object {
        $pemContent += "-----BEGIN CERTIFICATE-----`n"
        $pemContent += [Convert]::ToBase64String($_.RawData, 'InsertLineBreaks')
        $pemContent += "`n-----END CERTIFICATE-----`n"
    }
    if ($pemContent) {
        Set-Content -Path $winCaBundlePath -Value $pemContent -Encoding ASCII
        $env:NODE_EXTRA_CA_CERTS = $winCaBundlePath
        Write-Host "    CA bundle exported to $winCaBundlePath"
        Write-Host "    NODE_EXTRA_CA_CERTS set for this session."
    } else {
        Write-Host "    No corporate CA certificates found. VS Code extension installs may fail."
    }
}

# --- .wslconfig ---
Write-Host "`n==> Applying .wslconfig"
Copy-Item -Path ".\.wslconfig" -Destination "$OriginalUserProfile\.wslconfig" -Force

# --- Install distro (WSL feature must already be installed) ---
$installedDistros = (wsl --list --quiet 2>$null) -replace '\x00','' | Where-Object { $_.Trim() -ne '' }
if ($installedDistros -contains $DistroName) {
    Write-Host "`n==> $DistroName distro already installed, skipping download."
} else {
    Write-Host "`n==> Installing $DistroName distro"
    wsl --install -d $DistroName --no-launch
    if ($LASTEXITCODE -ne 0) { Write-Error "Failed to install $DistroName distro."; exit 1 }
}

# --- Create WSL user ---
Write-Host "`n==> Initializing WSL user..."
$userExists = wsl -d $DistroName -u root -- id -u $WSL_USER 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "    User '$WSL_USER' already exists, updating password."
    wsl -d $DistroName -u root -- bash -c "echo '${WSL_USER}:${PlainPass}' | chpasswd"
} else {
    wsl -d $DistroName -u root -- useradd -m -G sudo -s /bin/bash $WSL_USER
    wsl -d $DistroName -u root -- bash -c "echo '${WSL_USER}:${PlainPass}' | chpasswd"
}
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

# --- JetBrainsMono Nerd Font ---
Write-Host "`n==> Installing JetBrainsMono Nerd Font"
$fontRegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
$fontAlreadyInstalled = Get-ItemProperty -Path $fontRegPath |
    Get-Member -MemberType NoteProperty |
    Where-Object { $_.Name -match "JetBrainsMono" }

if ($fontAlreadyInstalled) {
    Write-Host "    JetBrainsMono Nerd Font is already installed, skipping download."
} else {
    $fontUrl = "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip"
    $fontZip = "$env:TEMP\JetBrainsMono.zip"
    $fontExtract = "$env:TEMP\JetBrainsMono"
    $fontsDir = "$env:SystemRoot\Fonts"
    $fontRegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"

    try {
        Invoke-WebRequest -Uri $fontUrl -OutFile $fontZip -UseBasicParsing
        if (Test-Path $fontExtract) { Remove-Item $fontExtract -Recurse -Force }
        Expand-Archive -Path $fontZip -DestinationPath $fontExtract -Force

        foreach ($font in Get-ChildItem -Path $fontExtract -Filter "*.ttf") {
            $destPath = "$fontsDir\$($font.Name)"
            if (-not (Test-Path $destPath)) {
                Copy-Item -Path $font.FullName -Destination $destPath -Force
                New-ItemProperty -Path $fontRegPath -Name "$($font.BaseName) (TrueType)" -Value $font.Name -PropertyType String -Force | Out-Null
                Write-Host "    Installed $($font.Name)"
            } else {
                Write-Host "    $($font.Name) already installed, skipping."
            }
        }
        Write-Host "    JetBrainsMono Nerd Font installed."
    } finally {
        Remove-Item $fontZip -ErrorAction SilentlyContinue
        Remove-Item $fontExtract -Recurse -ErrorAction SilentlyContinue
    }
}

# --- VS Code Remote-WSL + Dev Containers extensions (other extensions install inside WSL) ---
Write-Host "`n==> Installing VS Code host extensions"
# Temporarily override profile paths so 'code' installs to the correct (non-admin) user
$savedUserProfile = $env:USERPROFILE
$savedAppData = $env:APPDATA
$savedLocalAppData = $env:LOCALAPPDATA
$env:USERPROFILE = $OriginalUserProfile
$env:APPDATA = $OriginalAppData
$env:LOCALAPPDATA = $OriginalLocalAppData

code --install-extension ms-vscode-remote.remote-wsl --force
code --install-extension ms-vscode-remote.remote-containers --force

$env:USERPROFILE = $savedUserProfile
$env:APPDATA = $savedAppData
$env:LOCALAPPDATA = $savedLocalAppData

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
    $newTermSettings = Get-Content ".\terminal-settings.json" -Raw | ConvertFrom-Json
    if (Test-Path $terminalSettingsPath) {
        $existingTerm = Get-Content $terminalSettingsPath -Raw | ConvertFrom-Json
        # Preserve any auto-discovered profiles not in our config
        $newGuids = $newTermSettings.profiles.list | ForEach-Object { $_.guid }
        $extraProfiles = $existingTerm.profiles.list | Where-Object { $_.guid -notin $newGuids }
        if ($extraProfiles) {
            $newTermSettings.profiles.list = @($newTermSettings.profiles.list) + @($extraProfiles)
        }
    }
    $newTermSettings | ConvertTo-Json -Depth 10 | Set-Content $terminalSettingsPath -Encoding UTF8
    Write-Host "    Windows Terminal settings applied (existing profiles preserved)."
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
        Write-Host "    Repo already exists in WSL, syncing latest changes..."
        Copy-Item -Path "$repoRoot\*" -Destination $wslDest -Recurse -Force
        Write-Host "    Repo synced to WSL at ~/windev-bootstrap"
    } else {
        Copy-Item -Path $repoRoot -Destination $wslDest -Recurse -Force
        Write-Host "    Repo copied to WSL at ~/windev-bootstrap"
    }

    # Fix ownership (Copy-Item via UNC creates files owned by root)
    Write-Host "`n==> Fixing file ownership in WSL"
    wsl -d $DistroName -u root bash -c 'chown -R "$WSL_USER:$WSL_USER" "/home/$WSL_USER/windev-bootstrap"'
    if ($LASTEXITCODE -ne 0) { Write-Error "Failed to fix file ownership."; exit 1 }

    # --- Configure internal registry mirror (if selected) ---
    if ($UseInternalRegistry) {
        Write-Host "`n==> Configuring internal registry mirror"

        # Add registry-mirrors to daemon.json
        $daemonJsonPath = "$wslDest\wsl\docker\daemon.json"
        $daemonConfig = Get-Content $daemonJsonPath -Raw | ConvertFrom-Json
        $daemonConfig | Add-Member -MemberType NoteProperty -Name "registry-mirrors" -Value @("https://packagemanager.helsenord.no/docker-int-drift/") -Force
        $daemonConfig | ConvertTo-Json -Depth 10 | Set-Content $daemonJsonPath -Encoding UTF8

        # Add registries mirror to k3d config
        $k3dConfigPath = "$wslDest\wsl\k3d\k3d-dev.yaml"
        $k3dContent = Get-Content $k3dConfigPath -Raw
        $registriesBlock = "registries:`n  config: |`n    mirrors:`n      `"docker.io`":`n        endpoint:`n          - `"https://packagemanager.helsenord.no/docker-int-drift/`"`n"
        $k3dContent = $k3dContent -replace '(?m)^options:', "${registriesBlock}options:"
        Set-Content $k3dConfigPath -Value $k3dContent -Encoding UTF8

        Write-Host "    Internal registry mirror configured for Docker and k3d."
    }

    # --- Export and install corporate CA certificates ---
    if ($UseInternalRegistry) {
        Write-Host "`n==> Exporting corporate root CA certificates from Windows"
        $certDir = "$wslDest\certs"
        if (-not (Test-Path $certDir)) { New-Item -ItemType Directory -Path $certDir -Force | Out-Null }

        $exported = 0
        Get-ChildItem -Path Cert:\LocalMachine\Root | Where-Object {
            $_.Issuer -ne $_.Subject -or $_.Subject -match "Helse|helsenord|HN-"
        } | Where-Object { $_.Subject -match "Helse|helsenord|HN-" } | ForEach-Object {
            $name = ($_.Subject -replace '[^a-zA-Z0-9]', '_') -replace '__+', '_'
            $name = $name.Substring(0, [Math]::Min($name.Length, 60))
            $certPath = "$certDir\$name.crt"
            $pem = "-----BEGIN CERTIFICATE-----`n"
            $pem += [Convert]::ToBase64String($_.RawData, 'InsertLineBreaks')
            $pem += "`n-----END CERTIFICATE-----`n"
            Set-Content -Path $certPath -Value $pem -Encoding ASCII
            $exported++
            Write-Host "    Exported: $($_.Subject)"
        }

        if ($exported -eq 0) {
            Write-Host "    No corporate CA certificates found automatically."
            Write-Host "    If you have a .crt/.pem file, place it in $certDir before running WSL setup."
        } else {
            Write-Host "    Exported $exported certificate(s)."
        }
    }

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
