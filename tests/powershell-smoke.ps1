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
    & $cli workspace --env-file $profile 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { throw 'Stale lock was accepted' }
    $prepare = Join-Path $temp 'prepare'
    $current = Join-Path $prepare 'current'
    foreach ($repository in @((Join-Path $current 'runtime'),(Join-Path $current 'runtime/sources/frappe'),(Join-Path $current 'runtime/sources/apps/erpnext'))) {
        New-Item -ItemType Directory -Force -Path $repository | Out-Null
        & git -C $repository init -q
        & git -C $repository -c user.name=Test -c user.email=test@example.invalid commit --allow-empty -qm initial
        if ($LASTEXITCODE -ne 0) { throw 'Git fixture failed' }
    }
    $currentProfile = Join-Path $prepare 'current.env'
    "PROFILE=development`nPROJECT_NAME=prepare-test`nSITE_NAME=site.localhost`nWORKSPACE_DIR=current`nFRAPPE_MAJOR=16`nINSTALL_APPS=erpnext" | Set-Content $currentProfile
    $nextProfile = Join-Path $prepare 'next.env'
    & $cli app prepare --current-env-file $currentProfile --env-file $nextProfile | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'App target preparation failed' }
    $prepared = Get-Content $nextProfile -Raw
    if ($prepared -notmatch "FRAPPE_REF_KIND='commit'" -or $prepared -notmatch "FRAPPE_DOCKER_REF_KIND='commit'" -or $prepared -notmatch "APP_ERPNEXT_REF_KIND='commit'") { throw 'App target was not pinned' }
    & $cli app prepare --current-env-file $currentProfile --env-file $nextProfile 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { throw 'App prepare overwrote an existing target profile' }
    $backup=Join-Path $temp 'backup-fixture'
    New-Item -ItemType Directory -Path $backup | Out-Null
    $db=Join-Path $backup 'test-database.sql.gz'
    $stream=[IO.File]::Create($db)
    try { $compressed=[IO.Compression.GzipStream]::new($stream,[IO.Compression.CompressionLevel]::Optimal); try { $bytes=[Text.Encoding]::UTF8.GetBytes('SELECT 1;'); $compressed.Write($bytes,0,$bytes.Length) } finally { $compressed.Dispose() } } finally { $stream.Dispose() }
    'public' | Set-Content (Join-Path $temp 'public-marker')
    'private' | Set-Content (Join-Path $temp 'private-marker')
    & tar -czf (Join-Path $backup 'test-files.tgz') -C $temp public-marker
    & tar -czf (Join-Path $backup 'test-private-files.tgz') -C $temp private-marker
    '{}' | Set-Content (Join-Path $backup 'test-site_config_backup.json')
    "BACKUP_PROJECT='other-project'`nBACKUP_SITE='site.localhost'`nBACKUP_IMAGE='test:tag'" | Set-Content (Join-Path $backup 'manifest.env')
    $names=@('test-database.sql.gz','test-files.tgz','test-private-files.tgz','test-site_config_backup.json')
    $lines=foreach ($name in $names) { "$((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $backup $name)).Hash.ToLowerInvariant())  $name" }
    [IO.File]::WriteAllLines((Join-Path $backup 'SHA256SUMS'),[string[]]$lines)
    & $cli backup verify --backup-dir $backup | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Backup verification failed' }
    & $cli restore --env-file $currentProfile --backup-dir $backup --yes 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { throw 'Restore accepted an unrelated backup before Docker checks' }
    'corruption' | Add-Content (Join-Path $backup 'test-site_config_backup.json')
    & $cli backup verify --backup-dir $backup 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { throw 'Backup verification accepted a corrupted file' }
    'PASS PowerShell CLI smoke tests'
} finally { Remove-Item -Recurse -Force $temp }
exit 0
