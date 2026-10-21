[CmdletBinding()]
param(
    [string]$Version = $(if ($env:FRAPPEUP_VERSION) { $env:FRAPPEUP_VERSION } else { 'latest' }),
    [string]$InstallDir = $(if ($env:FRAPPEUP_INSTALL_DIR) { $env:FRAPPEUP_INSTALL_DIR } elseif (Test-Path (Join-Path $HOME '.frappe1tap\bin')) { Join-Path $HOME '.frappe1tap\bin' } else { Join-Path $HOME '.frappeup\bin' }),
    [Parameter(ValueFromRemainingArguments=$true)][string[]]$Command
)
$ErrorActionPreference = 'Stop'
$source = Split-Path -Parent $PSCommandPath
$temporary = $null
try {
    if (!(Test-Path (Join-Path $source 'frappeup.ps1'))) {
        $temporary = Join-Path ([IO.Path]::GetTempPath()) ('frappeup-' + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $temporary | Out-Null
        $repository = if ($env:FRAPPEUP_REPOSITORY) { $env:FRAPPEUP_REPOSITORY } else { 'tanishqpatil/FrappeUp' }
        $base = if ($Version -eq 'latest') { "https://github.com/$repository/releases/latest/download" } else { "https://github.com/$repository/releases/download/$Version" }
        $asset = 'frappeup_windows.zip'
        Invoke-WebRequest "$base/$asset" -OutFile (Join-Path $temporary $asset)
        Invoke-WebRequest "$base/$asset.sha256" -OutFile (Join-Path $temporary "$asset.sha256")
        $expected = ((Get-Content (Join-Path $temporary "$asset.sha256") -Raw).Trim() -split '\s+')[0]
        $actual = (Get-FileHash -Algorithm SHA256 (Join-Path $temporary $asset)).Hash
        if ($expected -ne $actual) { throw 'Release archive checksum mismatch' }
        Expand-Archive (Join-Path $temporary $asset) -DestinationPath $temporary
        $source = $temporary
    }
    $root = Split-Path -Parent $InstallDir
    New-Item -ItemType Directory -Force -Path $InstallDir, (Join-Path $root 'catalog') | Out-Null
    Copy-Item (Join-Path $source 'frappeup.ps1') (Join-Path $InstallDir 'frappeup.ps1') -Force
    Copy-Item (Join-Path $source 'frappeup.bat') (Join-Path $InstallDir 'frappeup.bat') -Force
    Copy-Item (Join-Path $source 'catalog\official-apps.env') (Join-Path $root 'catalog\official-apps.env') -Force
    Write-Host "Installed $(Join-Path $InstallDir 'frappeup.bat')"
    if ($Command.Count) { & (Join-Path $InstallDir 'frappeup.ps1') @Command; exit $LASTEXITCODE }
} finally {
    if ($temporary) { Remove-Item -Recurse -Force $temporary -ErrorAction SilentlyContinue }
}
