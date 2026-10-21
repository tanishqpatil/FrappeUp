[CmdletBinding()]
param(
    [string]$Version = $(if ($env:FRAPPE1TAP_VERSION) { $env:FRAPPE1TAP_VERSION } else { "latest" }),
    [string]$InstallDir = $(if ($env:FRAPPE1TAP_INSTALL_DIR) { $env:FRAPPE1TAP_INSTALL_DIR } else { Join-Path $HOME ".frappe1tap\bin" }),
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Command
)

$ErrorActionPreference = "Stop"
$repository = "SwayAlgo/Frappe1TapInstall"
$asset = "frappe1tap_windows_amd64.zip"
if ($Version -eq "latest") {
    $baseUrl = "https://github.com/$repository/releases/latest/download"
} else {
    $baseUrl = "https://github.com/$repository/releases/download/$Version"
}

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("frappe1tap-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
try {
    $archive = Join-Path $tempDir $asset
    $checksumFile = Join-Path $tempDir "$asset.sha256"
    Invoke-WebRequest -Uri "$baseUrl/$asset" -OutFile $archive
    Invoke-WebRequest -Uri "$baseUrl/$asset.sha256" -OutFile $checksumFile

    $expectedHash = ((Get-Content $checksumFile -Raw).Trim() -split '\s+')[0].ToUpperInvariant()
    $actualHash = (Get-FileHash -Algorithm SHA256 $archive).Hash.ToUpperInvariant()
    if ($expectedHash -ne $actualHash) {
        throw "Checksum verification failed for $asset."
    }

    Expand-Archive -Path $archive -DestinationPath $tempDir -Force
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Copy-Item (Join-Path $tempDir "frappe1tap.exe") (Join-Path $InstallDir "frappe1tap.exe") -Force
    Write-Host "Installed Frappe 1-Tap to $(Join-Path $InstallDir 'frappe1tap.exe')"
    if (-not (($env:Path -split ';') -contains $InstallDir)) {
        Write-Host "Add this directory to PATH: $InstallDir"
    }
    if ($Command.Count -gt 0) {
        & (Join-Path $InstallDir "frappe1tap.exe") @Command
        exit $LASTEXITCODE
    }
} finally {
    Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
}
