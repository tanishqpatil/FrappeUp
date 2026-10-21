$ErrorActionPreference = 'Stop'
$cli = Join-Path (Split-Path -Parent $PSScriptRoot) 'frappeup.ps1'
$temp = Join-Path ([IO.Path]::GetTempPath()) ('frappeup-test-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $temp | Out-Null
try {
    $profile = Join-Path $temp 'test.env'
    & $cli init --profile development --env-file $profile | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'init failed' }
    $workspace = Join-Path $temp '.frappeup/workspaces/frappeup-dev'
    New-Item -ItemType Directory -Force -Path $workspace | Out-Null
    "ADMIN_PASSWORD=test-secret`nDB_PASSWORD=private-db-secret" | Set-Content (Join-Path $workspace 'credentials.env')
    $credentials = & $cli credentials --env-file $profile
    if ($LASTEXITCODE -ne 0 -or !(($credentials -join "`n") -match 'Login: Administrator') -or !(($credentials -join "`n") -match 'Initial password: test-secret') -or (($credentials -join "`n") -match 'private-db-secret')) { throw 'Credential disclosure failed' }
    @'
INSTALL_APPS=hrms
FRAPPE_REF=0000000000000000000000000000000000000001
FRAPPE_REF_KIND=commit
FRAPPE_DOCKER_REF=0000000000000000000000000000000000000002
FRAPPE_DOCKER_REF_KIND=commit
APP_ERPNEXT_REF=0000000000000000000000000000000000000003
APP_ERPNEXT_REF_KIND=commit
APP_HRMS_REF=0000000000000000000000000000000000000004
APP_HRMS_REF_KIND=commit
'@ | Add-Content $profile
    $plan = & $cli plan --env-file $profile
    if ($LASTEXITCODE -ne 0 -or !(($plan -join "`n") -match '(?s)erpnext \[commit\].*hrms \[commit\]')) { throw 'Dependency plan failed' }
    & $cli lock --env-file $profile | Out-Null
    if ($LASTEXITCODE -ne 0 -or !(Test-Path "$profile.lock.env")) { throw 'commit lock failed' }
    Add-Content $profile 'SITE_NAME=changed.localhost'
    $result = & $cli workspace --env-file $profile 2>&1
    if ($LASTEXITCODE -eq 0 -or !(($result -join "`n") -match 'Lock does not match profile')) { throw 'Stale lock was accepted' }
    'PASS PowerShell CLI smoke tests'
} finally { Remove-Item -Recurse -Force $temp }
