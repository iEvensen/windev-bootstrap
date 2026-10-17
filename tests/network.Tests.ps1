$ErrorActionPreference = 'Stop'

$installerPath = Join-Path $PSScriptRoot '..\windows\install.ps1'
$tokens = $null
$parseErrors = $null
$installer = [System.Management.Automation.Language.Parser]::ParseFile(
    $installerPath, [ref]$tokens, [ref]$parseErrors
)
if ($parseErrors.Count -gt 0) { throw ($parseErrors | Out-String) }
$retryFunction = $installer.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq 'Invoke-NetworkRetry'
}, $true)
if (-not $retryFunction) { throw 'Retry helper not found.' }
. ([scriptblock]::Create($retryFunction.Extent.Text))

$script:attempts = 0
$script:delays = 0
function Start-Sleep { param([int]$Seconds) $script:delays++ }

Invoke-NetworkRetry -WarningAction SilentlyContinue -Operation {
    $script:attempts++
    if ($script:attempts -lt 3) { throw 'Temporary connection failure' }
}
if ($script:attempts -ne 3 -or $script:delays -ne 2) {
    throw 'Retry helper did not stop after success.'
}

$script:attempts = 0
$script:delays = 0
$caught = $false
try {
    Invoke-NetworkRetry -WarningAction SilentlyContinue -Operation {
        $script:attempts++
        throw 'Persistent connection failure'
    }
} catch {
    $caught = $_.Exception.Message -eq 'Persistent connection failure'
}
if (-not $caught -or $script:attempts -ne 4 -or $script:delays -ne 3) {
    throw 'Retry helper did not propagate the final exception.'
}

$script:attempts = 0
$script:delays = 0
Invoke-NetworkRetry -NativeCommand -WarningAction SilentlyContinue -Operation {
    $script:attempts++
    $global:LASTEXITCODE = if ($script:attempts -lt 2) { 7 } else { 0 }
}
if ($script:attempts -ne 2 -or $script:delays -ne 1) {
    throw 'Native command exit codes did not trigger retries.'
}

$script:attempts = 0
$script:delays = 0
$caught = $false
try {
    Invoke-NetworkRetry -NativeCommand -WarningAction SilentlyContinue -Operation {
        $script:attempts++
        $global:LASTEXITCODE = 7
    }
} catch {
    $caught = $_.Exception.Message -eq 'Download command failed with exit code 7.'
}
if (-not $caught -or $script:attempts -ne 4 -or $script:delays -ne 3) {
    throw 'Persistent native command failures were not propagated.'
}
$global:LASTEXITCODE = 0
Write-Output 'PASS PowerShell syntax, retry limits, early success, exceptions, and native exit codes'