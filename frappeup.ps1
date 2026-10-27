$Arguments = @($args)
$ErrorActionPreference = 'Stop'
$ScriptRoot = Split-Path -Parent $PSCommandPath
if (Test-Path (Join-Path $ScriptRoot 'catalog\official-apps.env')) { $Root = $ScriptRoot } else { $Root = Split-Path -Parent $ScriptRoot }
$CatalogPath = Join-Path $Root 'catalog\official-apps.env'
$Version = '0.4.0'

function Fail([string]$Message) { throw $Message }
function Read-Env([string]$Path,[string]$Kind='generic') {
    if (!(Test-Path $Path)) { Fail "Cannot read $Path" }
    $map = @{}
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        $line = $line.Trim()
        if (!$line -or $line.StartsWith('#')) { continue }
        if ($line -cnotmatch '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') { Fail "Invalid KEY=VALUE line in $Path" }
        $key=$Matches[1]; $value=$Matches[2]
        $allowed=switch ($Kind) {
            'profile' { $key -cmatch '^(PROFILE|PROJECT_NAME|SITE_NAME|WORKSPACE_DIR|FRAPPE_REPOSITORY|FRAPPE_REF|FRAPPE_REF_KIND|FRAPPE_DOCKER_REPOSITORY|FRAPPE_DOCKER_REF|FRAPPE_DOCKER_REF_KIND|FRAPPE_MAJOR|INSTALL_APPS|CUSTOM_APPS_FILE)$' -or $key -cmatch '^APP_[A-Z0-9_]+_REF(_KIND)?$' }
            'custom' { $key -ceq 'CUSTOM_APP_IDS' -or $key -cmatch '^APP_[A-Za-z0-9_]+_(DISPLAY_NAME|REPOSITORY|REF|REF_KIND|APP_NAME|REQUIRES|MAJORS)$' }
            'catalog' { $key -ceq 'APP_IDS' -or $key -cmatch '^APP_[A-Za-z0-9_]+_(DISPLAY_NAME|REPOSITORY|REF|REF_KIND|APP_NAME|REQUIRES|MAJORS)$' }
            'lock' { $key -cmatch '^LOCK_(SCHEMA|PLAN_SHA256|PROJECT_NAME|SITE_NAME|FRAPPE_REPOSITORY|FRAPPE_REF|FRAPPE_REF_KIND|FRAPPE_COMMIT|FRAPPE_DOCKER_REPOSITORY|FRAPPE_DOCKER_REF|FRAPPE_DOCKER_REF_KIND|FRAPPE_DOCKER_COMMIT|APP_IDS)$' -or $key -cmatch '^LOCK_APP_[A-Za-z0-9_]+_(REPOSITORY|REF|REF_KIND|APP_NAME|COMMIT)$' }
            'workspace' { $key -cmatch '^(WORKSPACE_PLAN_SHA256|IMAGE|TAG)$' }
            'generic' { $true }
            default { $false }
        }
        if (!$allowed -or $map.ContainsKey($key) -or $value.Contains("`t")) { Fail "Invalid, duplicate, or unsupported setting in $Path" }
        if ($value.StartsWith("'")) {
            if ($value.Length -lt 2 -or !$value.EndsWith("'")) { Fail "Invalid quoted value in $Path" }
            $inner=$value.Substring(1,$value.Length-2)
            if ($inner.Replace("'\''",'').Contains("'")) { Fail "Invalid quoted value in $Path" }
            $value=$inner.Replace("'\''", "'")
        } elseif ($value.StartsWith('"')) {
            if ($value.Length -lt 2 -or !$value.EndsWith('"')) { Fail "Invalid quoted value in $Path" }
            $value=$value.Substring(1,$value.Length-2)
            if ($value.Contains('"')) { Fail "Invalid quoted value in $Path" }
        } elseif ($value -match '\s' -or $value.IndexOfAny([char[]]@("'",'"','`','$',';','&','|','<','>','(',')')) -ge 0) { Fail "Invalid unquoted value in $Path" }
        if ($key -cmatch '_REF_KIND$' -and $value -cnotin @('branch','tag','commit')) { Fail "Invalid ref kind in $Path" }
        $map[$key] = $value
    }
    return $map
}
function Get-Val($Map,[string]$Key,[string]$Fallback='') { if ($Map.ContainsKey($Key) -and $Map[$Key]) { return [string]$Map[$Key] }; return $Fallback }
function Write-Env([string]$Path,$Map) {
    $lines = foreach ($key in ($Map.Keys | Sort-Object)) { $escaped=([string]$Map[$key]).Replace("'", "'\''"); "$key='$escaped'" }
    [IO.File]::WriteAllLines($Path,[string[]]$lines,[Text.UTF8Encoding]::new($false))
}
function Hash-Text([string]$Text) {
    $bytes=[Text.Encoding]::UTF8.GetBytes($Text)
    $hash=[Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
    return ([BitConverter]::ToString($hash)).Replace('-','').ToLowerInvariant()
}
function Run([string]$Name,[string[]]$CommandArgs) {
    & $Name @CommandArgs
    if ($LASTEXITCODE -ne 0) { Fail "$Name exited with code $LASTEXITCODE" }
}
function Parse-Options([string[]]$Items) {
    $options=@{}
    for ($i=0; $i -lt $Items.Count; $i++) {
        $name=$Items[$i]
        switch ($name) {
            {$_ -in '--force','--docker','--follow','--yes'} { $options[$name]=$true; break }
            {$_ -in '--profile','--env-file','--current-env-file','--backup-dir','--lock-file','--output','--lines','--existing'} {
                if ($i+1 -ge $Items.Count) { Fail "$name requires a value" }
                $options[$name]=$Items[++$i]; break
            }
            default { Fail "Unknown option $name" }
        }
    }
    return $options
}
function Load-Profile($Options) {
    if (!$Options['--env-file']) { Fail '--env-file is required' }
    $script:EnvPath=[IO.Path]::GetFullPath($Options['--env-file'])
    $script:Profile=Read-Env $EnvPath 'profile'
    $script:Profile['PROFILE']=Get-Val $Profile 'PROFILE' 'development'
    $script:Profile['PROJECT_NAME']=Get-Val $Profile 'PROJECT_NAME' 'frappeup'
    $script:Profile['SITE_NAME']=Get-Val $Profile 'SITE_NAME' 'site.localhost'
    $script:Profile['FRAPPE_REPOSITORY']=Get-Val $Profile 'FRAPPE_REPOSITORY' 'https://github.com/frappe/frappe'
    $script:Profile['FRAPPE_REF']=Get-Val $Profile 'FRAPPE_REF' 'version-16'
    $script:Profile['FRAPPE_REF_KIND']=Get-Val $Profile 'FRAPPE_REF_KIND' 'branch'
    $script:Profile['FRAPPE_DOCKER_REPOSITORY']=Get-Val $Profile 'FRAPPE_DOCKER_REPOSITORY' 'https://github.com/frappe/frappe_docker'
    $script:Profile['FRAPPE_DOCKER_REF']=Get-Val $Profile 'FRAPPE_DOCKER_REF' 'main'
    $script:Profile['FRAPPE_DOCKER_REF_KIND']=Get-Val $Profile 'FRAPPE_DOCKER_REF_KIND' 'branch'
    $script:Profile['FRAPPE_MAJOR']=Get-Val $Profile 'FRAPPE_MAJOR' '16'
    if ($Profile['PROFILE'] -cnotin 'development','production') { Fail 'PROFILE must be development or production' }
    if ($Profile['PROJECT_NAME'] -notmatch '^[A-Za-z0-9_-]+$') { Fail 'Invalid PROJECT_NAME' }
    if ($Profile['SITE_NAME'] -notmatch '^[A-Za-z0-9.-]+$') { Fail 'Invalid SITE_NAME' }
    if ($Profile['FRAPPE_MAJOR'] -notmatch '^[1-9][0-9]*$') { Fail 'Invalid FRAPPE_MAJOR' }
    $envDir=Split-Path -Parent $EnvPath
    $legacyWorkspace=Join-Path $envDir ".frappe1tap/workspaces/$($Profile['PROJECT_NAME'])"
    $workspace=Get-Val $Profile 'WORKSPACE_DIR' $(if (Test-Path $legacyWorkspace) { ".frappe1tap/workspaces/$($Profile['PROJECT_NAME'])" } else { ".frappeup/workspaces/$($Profile['PROJECT_NAME'])" })
    $script:WorkspacePath=[IO.Path]::GetFullPath((Join-Path $envDir $workspace))
    $script:LogDir=Join-Path $envDir $(if ($WorkspacePath -like '*.frappe1tap\workspaces\*') { '.frappe1tap/logs' } else { '.frappeup/logs' })
    $script:Catalog=Read-Env $CatalogPath 'catalog'
    $custom=Get-Val $Profile 'CUSTOM_APPS_FILE'
    if ($custom) {
        $customPath=[IO.Path]::GetFullPath((Join-Path $envDir $custom))
        $extra=Read-Env $customPath 'custom'
        foreach ($key in $extra.Keys) { $Catalog[$key]=$extra[$key] }
        $Catalog['APP_IDS'] += ' ' + (Get-Val $extra 'CUSTOM_APP_IDS')
    }
    $knownIds=@((Get-Val $Catalog 'APP_IDS') -split '\s+' | Where-Object { $_ } | ForEach-Object { $_.ToUpperInvariant() })
    foreach ($key in $Profile.Keys) {
        if ($key -cmatch '^APP_(.+)_REF(_KIND)?$' -and $knownIds -cnotcontains $Matches[1]) { Fail "Unknown app override: $key" }
    }
}
function App-Field([string]$Id,[string]$Field) {
    if ($Id -notmatch '^[A-Za-z0-9_]+$') { Fail "Invalid app id $Id" }
    return Get-Val $Catalog "APP_${Id}_$Field"
}
function App-Ref([string]$Id) { return Get-Val $Profile "APP_$($Id.ToUpperInvariant())_REF" (App-Field $Id 'REF') }
function App-Kind([string]$Id) { return Get-Val $Profile "APP_$($Id.ToUpperInvariant())_REF_KIND" (App-Field $Id 'REF_KIND') }
function Resolve-App([string]$Id) {
    if (!(App-Field $Id 'REPOSITORY')) { Fail "Unknown app $Id" }
    if ((App-Field $Id 'MAJORS') -split ' ' -notcontains $Profile['FRAPPE_MAJOR']) { Fail "$Id does not declare support for Frappe $($Profile['FRAPPE_MAJOR'])" }
    if ($script:Visit[$Id] -eq 'done') { return }
    if ($script:Visit[$Id] -eq 'visiting') { Fail "Cyclic dependency at $Id" }
    $script:Visit[$Id]='visiting'
    foreach ($dependency in ((App-Field $Id 'REQUIRES') -split '\s+')) { if ($dependency) { Resolve-App $dependency } }
    $script:Apps.Add($Id)
    $script:Visit[$Id]='done'
}
function Build-Plan {
    $script:Apps=[Collections.Generic.List[string]]::new()
    $script:Visit=@{}
    foreach ($id in ((Get-Val $Profile 'INSTALL_APPS') -split '[,\s]+')) { if ($id) { Resolve-App $id } }
}
function Plan-Hash {
    $text="project=$($Profile['PROJECT_NAME'])`nsite=$($Profile['SITE_NAME'])`nfrappe=$($Profile['FRAPPE_REPOSITORY'])@$($Profile['FRAPPE_REF'])|$($Profile['FRAPPE_REF_KIND'])`nfrappe_docker=$($Profile['FRAPPE_DOCKER_REPOSITORY'])@$($Profile['FRAPPE_DOCKER_REF'])|$($Profile['FRAPPE_DOCKER_REF_KIND'])`nmajor=$($Profile['FRAPPE_MAJOR'])`n"
    foreach ($id in $Apps) { $text+="app=$id|$(App-Field $id 'REPOSITORY')|$(App-Ref $id)|$(App-Kind $id)|$(App-Field $id 'APP_NAME')`n" }
    return Hash-Text $text
}
function Legacy-Plan-Hash {
    $text="project=$($Profile['PROJECT_NAME'])`nsite=$($Profile['SITE_NAME'])`nfrappe=$($Profile['FRAPPE_REPOSITORY'])@$($Profile['FRAPPE_REF'])`nfrappe_docker=$($Profile['FRAPPE_DOCKER_REPOSITORY'])@$($Profile['FRAPPE_DOCKER_REF'])`nmajor=$($Profile['FRAPPE_MAJOR'])`n"
    foreach ($id in $Apps) { $text+="app=$id|$(App-Field $id 'REPOSITORY')|$(App-Ref $id)|$(App-Field $id 'APP_NAME')`n" }
    return Hash-Text $text
}
function Resolve-Commit([string]$Repository,[string]$Ref,[string]$Kind) {
    if ($Kind -eq 'commit') { if ($Ref -notmatch '^[0-9a-fA-F]{40}$') { Fail 'Invalid commit' }; return $Ref }
    $refs = if ($Kind -eq 'tag') { @($Ref,"refs/tags/$Ref","refs/tags/$Ref^{}") } elseif ($Kind -eq 'branch') { @($Ref,"refs/heads/$Ref") } else { Fail "Invalid ref kind $Kind" }
    $rows = & git ls-remote $Repository @refs
    if ($LASTEXITCODE -ne 0) { Fail "Cannot resolve $Repository @ $Ref" }
    $target = if ($Kind -eq 'tag') { "refs/tags/$Ref^{}" } else { "refs/heads/$Ref" }
    foreach ($row in $rows) { $parts=$row -split '\s+'; if ($parts.Count -ge 2 -and $parts[1] -eq $target) { return $parts[0] } }
    foreach ($row in $rows) { $parts=$row -split '\s+'; if ($parts.Count -ge 2 -and $parts[1] -eq $Ref) { return $parts[0] } }
    Fail "Ref $Ref was not found in $Repository"
}
function Load-Lock($Options) {
    $script:LockPath=if ($Options['--lock-file']) { $Options['--lock-file'] } else { "$EnvPath.lock.env" }
    $script:Lock=Read-Env $LockPath 'lock'
    if ($Lock['LOCK_SCHEMA'] -eq '1') {
        if ($Lock['LOCK_PLAN_SHA256'] -ne (Legacy-Plan-Hash)) { Fail 'Lock does not match profile; run lock and workspace again' }
        if ($Profile['FRAPPE_REF_KIND'] -ne 'branch' -or $Profile['FRAPPE_DOCKER_REF_KIND'] -ne 'branch' -or (Get-Val $Profile 'CUSTOM_APPS_FILE')) { Fail 'Legacy lock cannot verify ref kinds; run lock and workspace again' }
        foreach ($id in $Apps) { if ((App-Kind $id) -ne (App-Field $id 'REF_KIND')) { Fail 'Legacy lock cannot verify app ref kind' } }
    } elseif ($Lock['LOCK_SCHEMA'] -eq '2') {
        if ($Lock['LOCK_PLAN_SHA256'] -ne (Plan-Hash)) { Fail 'Lock does not match profile; run lock and workspace again' }
        if ($Lock['LOCK_FRAPPE_REF_KIND'] -ne $Profile['FRAPPE_REF_KIND'] -or $Lock['LOCK_FRAPPE_DOCKER_REF_KIND'] -ne $Profile['FRAPPE_DOCKER_REF_KIND']) { Fail 'Lock ref kind does not match profile' }
        foreach ($id in $Apps) { if ($Lock["LOCK_APP_${id}_REF_KIND"] -ne (App-Kind $id)) { Fail "Lock ref kind does not match app $id" } }
    } else { Fail 'Unsupported lock file; run lock again' }
}
function Snapshot([string]$Repository,[string]$Commit,[string]$Destination) {
    Run git @('clone','--no-checkout','--filter=blob:none',$Repository,$Destination)
    Run git @('-C',$Destination,'fetch','--filter=blob:none','origin',$Commit)
    Run git @('-C',$Destination,'checkout','--detach',$Commit)
    Run git @('-C',$Destination,'branch','-f','frappeup-lock',$Commit)
}
function Doctor {
    Run docker @('version','--format','{{.Server.Version}}')
    Run docker @('compose','version')
    Run docker @('buildx','version')
}
function Log([string]$Event) {
    New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
    Add-Content (Join-Path $LogDir 'cli.log') "$(Get-Date -Format o) $Event"
}
function Existing-Site {
    $compose=Compose-Args
    $backend=& docker compose @compose ps -q backend 2>$null
    if ($LASTEXITCODE -ne 0 -or !$backend) { return $false }
    $actual=& docker inspect --format '{{.Config.Image}}' $backend
    $expected="frappeup/$($Profile['PROJECT_NAME']):$($Lock['LOCK_PLAN_SHA256'].Substring(0,12))"
    if ($actual -ne $expected) { Fail 'Existing Docker project uses a different locked image; choose a new PROJECT_NAME' }
    $installed=& docker compose @compose exec -T backend bench --site $Profile['SITE_NAME'] list-apps 2>$null
    if ($LASTEXITCODE -ne 0) { return $false }
    foreach ($id in $Apps) {
        $name=App-Field $id 'APP_NAME'
        if (-not ($installed | Where-Object { ($_ -split '\s+')[0] -eq $name })) { Fail "Existing site lacks $name; refusing to replace it" }
    }
    return $true
}
function Compose-Args([string]$Workspace=$WorkspacePath) {
    $runtime=Join-Path $Workspace 'runtime'
    $runtimeEnv=if (Test-Path (Join-Path $runtime '.frappeup.env')) { Join-Path $runtime '.frappeup.env' } else { Join-Path $runtime '.frappe1tap.env' }
    $siteCompose=if (Test-Path (Join-Path $runtime 'frappeup.create-site.yaml')) { Join-Path $runtime 'frappeup.create-site.yaml' } else { Join-Path $runtime 'frappe1tap.create-site.yaml' }
    $result=@('--env-file',$runtimeEnv,'--env-file',(Join-Path $Workspace 'credentials.env'),'-p',$Profile['PROJECT_NAME'],'-f',(Join-Path $runtime 'compose.yaml'),'-f',(Join-Path $runtime 'overrides/compose.mariadb.yaml'),'-f',(Join-Path $runtime 'overrides/compose.redis.yaml'),'-f',(Join-Path $runtime 'overrides/compose.noproxy.yaml'))
    if (Test-Path $siteCompose) { $result+=@('-f',$siteCompose) }
    return $result
}
function Project-Resources {
    $script:ProjectContainers=@(& docker ps -aq --filter "label=com.docker.compose.project=$($Profile['PROJECT_NAME'])")
    if ($LASTEXITCODE -ne 0) { Fail 'Cannot inspect Docker containers' }
    $script:ProjectVolumes=@(& docker volume ls -q --filter "label=com.docker.compose.project=$($Profile['PROJECT_NAME'])")
    if ($LASTEXITCODE -ne 0) { Fail 'Cannot inspect Docker volumes' }
    return [bool]($ProjectContainers.Count -or $ProjectVolumes.Count)
}
function Choose-Existing($Options) {
    Write-Host "Existing Docker project: $($Profile['PROJECT_NAME'])"
    if ($ProjectContainers.Count) { & docker ps -a --filter "label=com.docker.compose.project=$($Profile['PROJECT_NAME'])" --format '  container: {{.Names}} ({{.Status}})' | Out-Host }
    if ($ProjectVolumes.Count) { & docker volume ls --filter "label=com.docker.compose.project=$($Profile['PROJECT_NAME'])" --format '  volume: {{.Name}}' | Out-Host }
    if ($Options['--existing'] -and $Options['--existing'] -ne 'keep') { Fail '--existing supports keep only' }
    if ($Options['--existing'] -eq 'keep' -or [Console]::IsInputRedirected) { Write-Host 'Keeping existing data and deployment; no changes made.'; return $false }
    $answer=Read-Host 'Choose [K]eep data or [R]eset after a verified backup (default K)'
    if ($answer -in @('r','R','reset','RESET')) { return $true }
    if ($answer -in @('','k','K','keep','KEEP')) { Write-Host 'Keeping existing data and deployment; no changes made.'; return $false }
    Fail 'Invalid choice; no changes made'
}
function Backup-Site([string]$Workspace,[string]$Purpose) {
    $compose=Compose-Args $Workspace
    $backend=& docker compose @compose ps -q backend 2>$null
    if ($LASTEXITCODE -ne 0 -or !$backend) { Fail 'Backup requires a running backend; no data was changed' }
    & docker compose @compose exec -T backend bench --site $Profile['SITE_NAME'] list-apps *> $null
    if ($LASTEXITCODE -ne 0) { Fail 'Site is unavailable for backup; no data was changed' }
    $stamp=(Get-Date).ToUniversalTime().ToString('yyyyMMdd_HHmmss')
    $envDir=Split-Path -Parent $EnvPath
    $script:BackupDir=Join-Path $envDir ".frappeup/backups/$($Profile['PROJECT_NAME'])/$Purpose-$stamp-$PID"
    # Frappe expects private/backups to contain files only.
    $containerBackup="/home/frappe/frappe-bench/sites/.frappeup-backups/$($Profile['SITE_NAME'])/$Purpose-$stamp-$PID"
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
    & docker compose @compose exec -T backend bench --site $Profile['SITE_NAME'] backup --with-files --compress --backup-path $containerBackup
    if ($LASTEXITCODE -ne 0) { Fail "Backup failed; no data was changed (partial files: $BackupDir)" }
    & docker cp "${backend}:$containerBackup/." $BackupDir
    if ($LASTEXITCODE -ne 0) { Fail "Backup export failed; no data was changed (partial files: $BackupDir)" }
    $archives=@{}
    foreach ($pattern in @('*-database*.sql.gz','*-files.tgz','*-private-files.tgz','*-site_config_backup.json')) {
        $files=@(Get-ChildItem -Path $BackupDir -File -Filter $pattern | Where-Object Length -gt 0)
        if ($pattern -eq '*-files.tgz') { $files=@($files | Where-Object Name -NotLike '*-private-files.tgz') }
        if (!$files.Count) { Fail "Backup is missing $pattern; no data was changed" }
        $archives[$pattern]=$files[0]
    }
    $database=[IO.File]::OpenRead($archives['*-database*.sql.gz'].FullName)
    try {
        $compressed=[IO.Compression.GzipStream]::new($database,[IO.Compression.CompressionMode]::Decompress)
        try { $compressed.CopyTo([IO.Stream]::Null) } finally { $compressed.Dispose() }
    } catch { Fail 'Database archive is corrupt; no data was changed' } finally { $database.Dispose() }
    foreach ($pattern in @('*-files.tgz','*-private-files.tgz')) {
        & tar -tzf $archives[$pattern].FullName *> $null
        if ($LASTEXITCODE -ne 0) { Fail "$pattern archive is corrupt; no data was changed" }
    }
    try { Get-Content $archives['*-site_config_backup.json'].FullName -Raw | ConvertFrom-Json | Out-Null }
    catch { Fail 'Site configuration backup is corrupt; no data was changed' }
    $checksums=foreach ($pattern in @('*-database*.sql.gz','*-files.tgz','*-private-files.tgz','*-site_config_backup.json')) {
        $file=$archives[$pattern]
        "$((Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash.ToLowerInvariant())  $($file.Name)"
    }
    [IO.File]::WriteAllLines((Join-Path $BackupDir 'SHA256SUMS'),[string[]]$checksums,[Text.UTF8Encoding]::new($false))
    $backupImage=& docker inspect --format '{{.Config.Image}}' $backend
    if ($LASTEXITCODE -ne 0) { Fail 'Cannot verify backup source image; no data was changed' }
    Write-Env (Join-Path $BackupDir 'manifest.env') @{BACKUP_PROJECT=$Profile['PROJECT_NAME']; BACKUP_SITE=$Profile['SITE_NAME']; BACKUP_IMAGE=$backupImage; BACKUP_CREATED_UTC=(Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')}
    Write-Host "Validated backup archives: $BackupDir"
}
function Backup-Before-Reset { Backup-Site $WorkspacePath 'reset' }
function Verify-Backup([string]$Path) {
    if (!$Path -or !(Test-Path -LiteralPath $Path -PathType Container)) { Fail '--backup-dir must name an existing backup directory' }
    $path=(Resolve-Path -LiteralPath $Path).Path
    $manifest=Join-Path $path 'manifest.env'; $checksums=Join-Path $path 'SHA256SUMS'
    if (!(Test-Path $manifest) -or !(Test-Path $checksums)) { Fail 'Backup manifest or checksums are missing' }
    Read-Env $manifest | Out-Null
    $lines=@(Get-Content -LiteralPath $checksums)
    if ($lines.Count -ne 4) { Fail 'Backup must contain four checksummed artifacts' }
    foreach ($line in $lines) {
        if ($line -notmatch '^([0-9a-f]{64})  ([A-Za-z0-9_.-]+)$' -or $Matches[2].Contains('..')) { Fail 'Invalid backup checksum line' }
        $file=Join-Path $path $Matches[2]
        if (!(Test-Path -LiteralPath $file -PathType Leaf)) { Fail "Backup artifact is missing: $file" }
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath $file).Hash.ToLowerInvariant() -ne $Matches[1]) { Fail "Backup checksum mismatch: $file" }
    }
    $artifacts=@{}
    foreach ($pattern in @('*-database*.sql.gz','*-files.tgz','*-private-files.tgz','*-site_config_backup.json')) {
        $files=@(Get-ChildItem -LiteralPath $path -File -Filter $pattern | Where-Object { $pattern -ne '*-files.tgz' -or $_.Name -notlike '*-private-files.tgz' })
        if ($files.Count -ne 1) { Fail "Backup archive set is incomplete or ambiguous: $pattern" }
        $artifacts[$pattern]=$files[0]
    }
    $database=[IO.File]::OpenRead($artifacts['*-database*.sql.gz'].FullName)
    try { $compressed=[IO.Compression.GzipStream]::new($database,[IO.Compression.CompressionMode]::Decompress); try { $compressed.CopyTo([IO.Stream]::Null) } finally { $compressed.Dispose() } }
    catch { Fail 'Database archive integrity check failed' }
    finally { $database.Dispose() }
    foreach ($pattern in @('*-files.tgz','*-private-files.tgz')) { & tar -tzf $artifacts[$pattern].FullName *> $null; if ($LASTEXITCODE -ne 0) { Fail "$pattern archive integrity check failed" } }
    try { Get-Content $artifacts['*-site_config_backup.json'].FullName -Raw | ConvertFrom-Json | Out-Null } catch { Fail 'Site configuration backup is corrupt' }
    "PASS backup checksums and archive integrity: $path"
}
function Restore-Site($Options) {
    $requested=Get-Val $Options '--backup-dir'
    Verify-Backup $requested | Out-Host
    $backupDir=(Resolve-Path -LiteralPath $requested).Path
    if ($Profile['PROFILE'] -ne 'development') { Fail 'Restore currently supports development profiles only' }
    $manifest=Read-Env (Join-Path $backupDir 'manifest.env')
    if ($manifest['BACKUP_PROJECT'] -ne $Profile['PROJECT_NAME'] -or $manifest['BACKUP_SITE'] -ne $Profile['SITE_NAME']) { Fail 'Backup belongs to a different project or site' }
    $runtime=Join-Path $WorkspacePath 'runtime'
    $runtimeEnv=if (Test-Path (Join-Path $runtime '.frappeup.env')) { Join-Path $runtime '.frappeup.env' } else { Join-Path $runtime '.frappe1tap.env' }
    if (!(Test-Path $runtimeEnv) -or !(Test-Path (Join-Path $WorkspacePath 'credentials.env'))) { Fail 'Restore workspace is incomplete' }
    $runtimeMeta=Read-Env $runtimeEnv
    $restoreImage="$($runtimeMeta['CUSTOM_IMAGE']):$($runtimeMeta['CUSTOM_TAG'])"
    if ($manifest['BACKUP_IMAGE'] -ne $restoreImage) { Fail 'Backup image does not match restore profile; use the profile and image from the backup checkpoint' }
    Doctor | Out-Null
    & docker image inspect $restoreImage *> $null
    if ($LASTEXITCODE -ne 0) { Fail "Restore image is unavailable: $restoreImage" }
    if (!(Project-Resources) -or $ProjectVolumes -notcontains "$($Profile['PROJECT_NAME'])_sites") { Fail 'Site volume is missing; refusing to create a new site during restore' }
    if (!$Options['--yes']) {
        if ([Console]::IsInputRedirected) { Fail 'restore requires an interactive confirmation or --yes' }
        $confirmation=Read-Host "Type RESTORE $($Profile['PROJECT_NAME']) to overwrite site data from $backupDir"
        if ($confirmation -ne "RESTORE $($Profile['PROJECT_NAME'])") { Fail 'Restore cancelled; no data was changed' }
    }
    $lockRoot=Join-Path $Root '.frappeup/locks'
    New-Item -ItemType Directory -Force -Path $lockRoot | Out-Null
    $mutex=Join-Path $lockRoot "$($Profile['PROJECT_NAME']).lock"
    if (Test-Path $mutex) { Fail "Another operation may be active: $mutex" }
    New-Item -ItemType Directory -Path $mutex -ErrorAction Stop | Out-Null
    $mutationStarted=$false
    try {
        $override=Join-Path $WorkspacePath 'frappeup.restore.yaml'
        [IO.File]::WriteAllText($override,"services:`n  backend:`n    environment:`n      FRAPPEUP_DB_PASSWORD: `${DB_PASSWORD}`n",[Text.UTF8Encoding]::new($false))
        $compose=Compose-Args $WorkspacePath
        $restoreCompose=$compose+@('-f',$override)
        Run docker (@('compose')+$restoreCompose+@('config','-q'))
        $mutationStarted=$true
        Run docker (@('compose')+$compose+@('stop','frontend','backend','websocket','queue-short','queue-long','scheduler'))
        Run docker (@('compose')+$compose+@('up','-d','db','redis-cache','redis-queue'))
        $archives=@{}
        foreach ($pattern in @('*-database*.sql.gz','*-files.tgz','*-private-files.tgz')) {
            $files=@(Get-ChildItem -LiteralPath $backupDir -File -Filter $pattern | Where-Object { $pattern -ne '*-files.tgz' -or $_.Name -notlike '*-private-files.tgz' })
            $archives[$pattern]=$files[0].Name
        }
        $site=$Profile['SITE_NAME']
        $script='set -e; ls -1 apps > sites/apps.txt; bench --site ' + $site + ' restore /restore/' + $archives['*-database*.sql.gz'] + ' --with-public-files /restore/' + $archives['*-files.tgz'] + ' --with-private-files /restore/' + $archives['*-private-files.tgz'] + ' --db-root-password=$FRAPPEUP_DB_PASSWORD --force'
        Run docker (@('compose')+$restoreCompose+@('run','--rm','--no-deps','-v',"${backupDir}:/restore:ro",'backend','bash','-lc',$script))
        Run docker (@('compose')+$compose+@('up','-d','--no-deps','backend','websocket','queue-short','queue-long','scheduler','frontend'))
        $inventory=& docker compose @compose exec -T backend bench --site $site list-apps
        if ($LASTEXITCODE -ne 0) { Fail 'Restored site inventory is unavailable' }
        $names=@(foreach ($line in $inventory) { if ($line -match '^\s*([A-Za-z][A-Za-z0-9_]*)\s+') { $Matches[1] } })
        Build-Plan
        foreach ($id in $Apps) { $name=App-Field $id 'APP_NAME'; if ($names -notcontains $name) { Fail "Restored site lacks app $name" } }
        $probe='import requests,sys; r=requests.get("http://frontend:8080",headers={"Host":sys.argv[1]},timeout=30); print("HTTP",r.status_code); sys.exit(0 if r.status_code in (200,302,303) else 1)'
        Run docker (@('compose')+$compose+@('exec','-T','backend','python','-c',$probe,$site))
        $mutationStarted=$false
        Log "restore.completed $($Profile['PROJECT_NAME']) $backupDir"
        "Restored $site from $backupDir with $restoreImage"
    } catch {
        if ($mutationStarted) { [Console]::Error.WriteLine('Restore stopped after changing the project. Inspect Docker logs; do not start an unverified image.') }
        throw
    } finally { Remove-Item -LiteralPath $mutex -Force -ErrorAction SilentlyContinue }
}
function Reset-Project {
    Backup-Before-Reset | Out-Host
    $confirmation=Read-Host "Type RESET $($Profile['PROJECT_NAME']) to remove its Docker volumes"
    if ($confirmation -ne "RESET $($Profile['PROJECT_NAME'])") { Write-Host 'Reset cancelled; existing data is unchanged.'; return $false }
    $compose=Compose-Args
    Run docker (@('compose')+$compose+@('down','--volumes','--remove-orphans')) | Out-Host
    Log 'reset.completed'
    Write-Host "Reset project $($Profile['PROJECT_NAME']); backup remains at $BackupDir"
    return $true
}
function App-Prepare($Options) {
    if (!$Options['--current-env-file'] -or !$Options['--env-file']) { Fail 'app prepare requires --current-env-file and --env-file' }
    $targetPath=[IO.Path]::GetFullPath($Options['--env-file'])
    if (Test-Path $targetPath) { Fail "Target profile already exists: $targetPath" }
    Load-Profile @{'--env-file'=$Options['--current-env-file']}
    Build-Plan
    if ($Profile['PROFILE'] -ne 'development') { Fail 'app prepare currently supports development profiles only' }
    $frappe=& git -C (Join-Path $WorkspacePath 'runtime/sources/frappe') rev-parse HEAD 2>$null
    if ($LASTEXITCODE -ne 0) { Fail 'Cannot read current Frappe commit' }
    $dockerCommit=& git -C (Join-Path $WorkspacePath 'runtime') rev-parse HEAD 2>$null
    if ($LASTEXITCODE -ne 0) { Fail 'Cannot read current Frappe Docker commit' }
    $targetDir=Split-Path -Parent $targetPath
    $targetName=[IO.Path]::GetFileNameWithoutExtension($targetPath)
    $targetWorkspace=Join-Path $targetDir ".frappeup/workspaces/$($Profile['PROJECT_NAME'])-$targetName"
    if (Test-Path $targetWorkspace) { Fail "Target workspace already exists: $targetWorkspace" }
    $result=@{PROFILE=$Profile['PROFILE']; PROJECT_NAME=$Profile['PROJECT_NAME']; SITE_NAME=$Profile['SITE_NAME']; WORKSPACE_DIR=$targetWorkspace; FRAPPE_REPOSITORY=$Profile['FRAPPE_REPOSITORY']; FRAPPE_REF=$frappe; FRAPPE_REF_KIND='commit'; FRAPPE_DOCKER_REPOSITORY=$Profile['FRAPPE_DOCKER_REPOSITORY']; FRAPPE_DOCKER_REF=$dockerCommit; FRAPPE_DOCKER_REF_KIND='commit'; FRAPPE_MAJOR=$Profile['FRAPPE_MAJOR']; INSTALL_APPS=(Get-Val $Profile 'INSTALL_APPS')}
    $custom=Get-Val $Profile 'CUSTOM_APPS_FILE'
    if ($custom) { $result['CUSTOM_APPS_FILE']=[IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $EnvPath) $custom)) }
    foreach ($id in $Apps) {
        $commit=& git -C (Join-Path $WorkspacePath "runtime/sources/apps/$id") rev-parse HEAD 2>$null
        if ($LASTEXITCODE -ne 0) { Fail "Cannot read current commit for $id" }
        $key=$id.ToUpperInvariant()
        $result["APP_${key}_REF"]=$commit; $result["APP_${key}_REF_KIND"]='commit'
    }
    Write-Env $targetPath $result
    "Created $targetPath`nEdit INSTALL_APPS or app refs, then run lock and workspace for this target profile."
}
function App-Plan($Options) {
    if (!$Options['--current-env-file'] -or !$Options['--env-file']) { Fail 'app plan/apply requires --current-env-file and --env-file' }
    Load-Profile @{'--env-file'=$Options['--current-env-file']}
    $script:CurrentProject=$Profile['PROJECT_NAME']; $script:CurrentSite=$Profile['SITE_NAME']; $script:CurrentProfile=$Profile['PROFILE']; $script:CurrentWorkspace=$WorkspacePath
    Load-Profile $Options
    Build-Plan
    Load-Lock $Options
    if ($Profile['PROFILE'] -ne 'development' -or $CurrentProfile -ne 'development') { Fail 'App updates currently support development profiles only' }
    if ($Profile['PROJECT_NAME'] -ne $CurrentProject -or $Profile['SITE_NAME'] -ne $CurrentSite) { Fail 'Current and target profiles must use the same project and site' }
    if (!(Test-Path $CurrentWorkspace) -or !(Test-Path $WorkspacePath)) { Fail 'Both current and target workspaces must exist' }
    $script:CurrentWorkspace=(Resolve-Path -LiteralPath $CurrentWorkspace).Path
    $script:WorkspacePath=(Resolve-Path -LiteralPath $WorkspacePath).Path
    if ($CurrentWorkspace -eq $WorkspacePath) { Fail 'Target needs a separate WORKSPACE_DIR; preserve the current workspace' }
    $targetRuntime=Join-Path $WorkspacePath 'runtime'
    foreach ($needed in @((Join-Path $targetRuntime 'images/custom/Containerfile'),(Join-Path $targetRuntime 'apps.json'),(Join-Path $WorkspacePath 'workspace.env'),(Join-Path $WorkspacePath 'credentials.env'),(Join-Path $CurrentWorkspace 'credentials.env'),(Join-Path $CurrentWorkspace 'runtime/compose.yaml'))) {
        if (!(Test-Path $needed)) { Fail "Workspace is incomplete: $needed" }
    }
    $metadata=Read-Env (Join-Path $WorkspacePath 'workspace.env') 'workspace'
    if ($metadata['WORKSPACE_PLAN_SHA256'] -ne $Lock['LOCK_PLAN_SHA256']) { Fail 'Target workspace does not match its lock' }
    $currentFrappe=& git -C (Join-Path $CurrentWorkspace 'runtime/sources/frappe') rev-parse HEAD 2>$null
    if ($LASTEXITCODE -ne 0 -or $currentFrappe -ne $Lock['LOCK_FRAPPE_COMMIT']) { Fail 'Frappe core changed; this first app-update path supports app changes only' }
    $currentDocker=& git -C (Join-Path $CurrentWorkspace 'runtime') rev-parse HEAD 2>$null
    if ($LASTEXITCODE -ne 0 -or $currentDocker -ne $Lock['LOCK_FRAPPE_DOCKER_COMMIT']) { Fail 'Frappe Docker changed; pin its current commit for this app update' }
    $targetFrappeSource=Join-Path $WorkspacePath 'runtime/sources/frappe'
    $targetFrappe=& git -C $targetFrappeSource rev-parse HEAD 2>$null
    if ($LASTEXITCODE -ne 0 -or $targetFrappe -ne $Lock['LOCK_FRAPPE_COMMIT']) { Fail 'Target Frappe source does not match the lock' }
    $targetDocker=& git -C (Join-Path $WorkspacePath 'runtime') rev-parse HEAD 2>$null
    if ($LASTEXITCODE -ne 0 -or $targetDocker -ne $Lock['LOCK_FRAPPE_DOCKER_COMMIT']) { Fail 'Target Frappe Docker source does not match the lock' }
    $dirty=@(& git -C $targetFrappeSource status --porcelain)
    if ($LASTEXITCODE -ne 0 -or $dirty.Count) { Fail 'Target Frappe source has uncommitted changes' }
    Doctor | Out-Null
    $currentCompose=Compose-Args $CurrentWorkspace
    $backend=& docker compose @currentCompose ps -q backend 2>$null
    if ($LASTEXITCODE -ne 0 -or !$backend) { Fail 'Current backend is not running; no data was changed' }
    $owner=& docker inspect --format '{{index .Config.Labels "com.docker.compose.project"}}' $backend
    $files=& docker inspect --format '{{index .Config.Labels "com.docker.compose.project.config_files"}}' $backend
    if ($owner -ne $Profile['PROJECT_NAME'] -or (($files -split ',') -notcontains (Join-Path $CurrentWorkspace 'runtime/compose.yaml'))) { Fail 'Running backend was not created from the current workspace' }
    $runtimeEnv=if (Test-Path (Join-Path $CurrentWorkspace 'runtime/.frappeup.env')) { Join-Path $CurrentWorkspace 'runtime/.frappeup.env' } else { Join-Path $CurrentWorkspace 'runtime/.frappe1tap.env' }
    $script:currentImageMeta=Read-Env $runtimeEnv
    $actualImage=& docker inspect --format '{{.Config.Image}}' $backend
    if ($actualImage -ne "$($currentImageMeta['CUSTOM_IMAGE']):$($currentImageMeta['CUSTOM_TAG'])") { Fail 'Running backend image does not match current workspace' }
    $inventory=& docker compose @currentCompose exec -T backend bench --site $Profile['SITE_NAME'] list-apps
    if ($LASTEXITCODE -ne 0) { Fail 'Cannot read current site app inventory' }
    $installed=@(foreach ($line in $inventory) { if ($line -match '^\s*([A-Za-z][A-Za-z0-9_]*)\s+') { $Matches[1] } })
    if ($installed -notcontains 'frappe') { Fail 'Target is not a valid Frappe site' }
    $script:DesiredNames=[Collections.Generic.List[string]]::new(); $DesiredNames.Add('frappe')
    $script:NewApps=[Collections.Generic.List[string]]::new(); $script:ChangedApps=[Collections.Generic.List[string]]::new()
    foreach ($id in $Apps) {
        $name=App-Field $id 'APP_NAME'
        if ($name -notmatch '^[A-Za-z][A-Za-z0-9_]*$') { Fail "Invalid app package name $name" }
        $DesiredNames.Add($name)
        if (!$Lock["LOCK_APP_${id}_COMMIT"]) { Fail "Target lock lacks app $id" }
        $targetSource=Join-Path $WorkspacePath "runtime/sources/apps/$id"
        $targetCommit=& git -C $targetSource rev-parse HEAD 2>$null
        if ($LASTEXITCODE -ne 0 -or $targetCommit -ne $Lock["LOCK_APP_${id}_COMMIT"]) { Fail "Target source for $name does not match the lock" }
        $dirty=@(& git -C $targetSource status --porcelain)
        if ($LASTEXITCODE -ne 0 -or $dirty.Count) { Fail "Target source for $name has uncommitted changes" }
        if ($installed -contains $name) {
            $source=Join-Path $CurrentWorkspace "runtime/sources/apps/$id"
            if (!(Test-Path $source)) { Fail "Cannot verify current source for installed app $name" }
            $commit=& git -C $source rev-parse HEAD 2>$null
            if ($LASTEXITCODE -ne 0) { Fail "Cannot verify current commit for $name" }
            if ($commit -ne $targetCommit) {
                & git -C $targetSource merge-base --is-ancestor $commit $targetCommit 2>$null
                if ($LASTEXITCODE -ne 0) { Fail "App $name target is not a forward update; downgrades and branch switches need a separate workflow" }
                $ChangedApps.Add($name)
            }
        } else { $NewApps.Add($name) }
    }
    foreach ($name in $installed) { if ($DesiredNames -notcontains $name) { Fail "Target omits installed app $name; app removal is not supported" } }
    "Project: $($Profile['PROJECT_NAME'])`nSite: $($Profile['SITE_NAME'])`nCurrent image: $actualImage`nTarget lock: $($Lock['LOCK_PLAN_SHA256'])`nNew apps: $(if ($NewApps.Count) { $NewApps -join ' ' } else { 'none' })`nUpdated apps: $(if ($ChangedApps.Count) { $ChangedApps -join ' ' } else { 'none' })"
    'The app update takes a full backup, pauses application services, migrates the preserved site, then verifies service and site health. Writes and web requests will be unavailable during migration.'
}
function App-Phase([string]$Phase) {
    if ($script:OperationFile) { Add-Content -LiteralPath $script:OperationFile -Value "$((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')) $Phase" }
}
function App-Apply($Options) {
    App-Plan $Options | Out-Host
    if (!$NewApps.Count -and !$ChangedApps.Count) { 'Site already matches the target app commits; no change made.'; return }
    if (!$Options['--yes']) {
        if ([Console]::IsInputRedirected) { Fail 'app apply requires an interactive confirmation or --yes' }
        $confirmation=Read-Host "Type APPLY $($Profile['PROJECT_NAME']) to continue"
        if ($confirmation -ne "APPLY $($Profile['PROJECT_NAME'])") { Fail 'App update cancelled; no data was changed' }
    }
    $lockRoot=Join-Path $Root '.frappeup/locks'
    New-Item -ItemType Directory -Force -Path $lockRoot | Out-Null
    $mutex=Join-Path $lockRoot "$($Profile['PROJECT_NAME']).lock"
    if (Test-Path $mutex) { Fail "Another app update may be active: $mutex" }
    New-Item -ItemType Directory -Path $mutex -ErrorAction Stop | Out-Null
    $mutationStarted=$false
    $servicesPaused=$false
    $migrationStarted=$false
    try {
        $journalDir=Join-Path $CurrentWorkspace '.frappeup-operations'
        New-Item -ItemType Directory -Force -Path $journalDir | Out-Null
        $script:OperationFile=Join-Path $journalDir "update-$((Get-Date).ToUniversalTime().ToString('yyyyMMdd_HHmmss'))-$PID.log"
        App-Phase 'acquired'
        Copy-Item -LiteralPath (Join-Path $CurrentWorkspace 'credentials.env') -Destination (Join-Path $WorkspacePath 'credentials.env') -Force
        $runtime=Join-Path $WorkspacePath 'runtime'
        $image="frappeup/$($Profile['PROJECT_NAME'])"; $tag=$Lock['LOCK_PLAN_SHA256'].Substring(0,12)
        Run docker @('buildx','build','--platform','linux/amd64','--load','--tag',"${image}:$tag",'--file',(Join-Path $runtime 'images/custom/Containerfile'),'--secret',"id=apps_json,src=$(Join-Path $runtime 'apps.json')",$runtime)
        $imageId=& docker image inspect --format '{{.Id}}' "${image}:$tag"
        if ($LASTEXITCODE -ne 0) { Fail 'Built image is unavailable' }
        App-Phase "built $imageId"
        $runtimeSettings=@{CUSTOM_IMAGE=$image; CUSTOM_TAG=$tag; PULL_POLICY='never'; FRAPPE_SITE_NAME_HEADER=$Profile['SITE_NAME']}
        foreach ($key in @('HTTP_PUBLISH_PORT','NGINX_LISTEN_PORT')) { if ($currentImageMeta[$key]) { $runtimeSettings[$key]=$currentImageMeta[$key] } }
        Write-Env (Join-Path $runtime '.frappeup.env') $runtimeSettings
        $targetCompose=Compose-Args $WorkspacePath
        Run docker (@('compose')+$targetCompose+@('config','-q'))
        $currentCompose=Compose-Args $CurrentWorkspace
        $servicesPaused=$true
        Run docker (@('compose')+$currentCompose+@('stop','frontend','websocket','queue-short','queue-long','scheduler'))
        App-Phase 'writes_paused'
        Backup-Site $CurrentWorkspace 'update'
        App-Phase "backup $BackupDir"
        "Backup checkpoint: $BackupDir"
        Log "app.update.backup $($Profile['PROJECT_NAME']) $BackupDir"
        $mutationStarted=$true
        Run docker (@('compose')+$currentCompose+@('stop','backend'))
        App-Phase 'services_stopped'
        $site=$Profile['SITE_NAME']; $migrationScript='set -e; ls -1 apps > sites/apps.txt;'
        foreach ($app in $NewApps) { $migrationScript += " bench --site $site install-app $app;" }
        $migrationScript += " bench --site $site migrate;"
        $migrationStarted=$true
        Run docker (@('compose')+$targetCompose+@('run','--rm','--no-deps','backend','bash','-lc',$migrationScript))
        App-Phase 'migrated'
        Run docker (@('compose')+$targetCompose+@('up','-d','--no-deps','backend','websocket','queue-short','queue-long','scheduler','frontend'))
        App-Phase 'services_started'
        foreach ($service in @('backend','websocket','queue-short','queue-long','scheduler','frontend')) {
            $running=$false
            for ($attempt=0; $attempt -lt 30; $attempt++) {
                $id=& docker compose @targetCompose ps --status running -q $service 2>$null
                if ($LASTEXITCODE -eq 0 -and $id) { $running=$true; break }
                Start-Sleep -Seconds 2
            }
            if (!$running) { Fail "$service did not become running" }
        }
        $verified=& docker compose @targetCompose exec -T backend bench --site $site list-apps
        if ($LASTEXITCODE -ne 0) { Fail 'Updated site inventory is unavailable' }
        $verifiedNames=@(foreach ($line in $verified) { if ($line -match '^\s*([A-Za-z][A-Za-z0-9_]*)\s+') { $Matches[1] } })
        foreach ($name in $DesiredNames) { if ($verifiedNames -notcontains $name) { Fail "Updated site lacks app $name" } }
        $probe='import requests,sys; r=requests.get("http://frontend:8080",headers={"Host":sys.argv[1]},timeout=30); print("HTTP",r.status_code); sys.exit(0 if r.status_code in (200,302,303) else 1)'
        Run docker (@('compose')+$targetCompose+@('exec','-T','backend','python','-c',$probe,$site))
        $mutationStarted=$false
        $servicesPaused=$false
        App-Phase 'verified'
        Log "app.update.completed $($Profile['PROJECT_NAME']) $imageId"
        "Updated $site with image ${image}:$tag; data volumes were preserved.`nBackup: $BackupDir`nOperation log: $OperationFile"
    } catch {
        App-Phase 'failed'
        if ($servicesPaused -and !$migrationStarted) {
            try { Run docker (@('compose')+$currentCompose+@('up','-d','--no-deps','backend','frontend','websocket','queue-short','queue-long','scheduler')) }
            catch { [Console]::Error.WriteLine('Could not restart the original services; inspect Docker logs.') }
        }
        if ($mutationStarted) {
            [Console]::Error.WriteLine("Update stopped after the backup checkpoint. Site data may have changed; do not roll back the image alone. Backup: $BackupDir")
            [Console]::Error.WriteLine('Inspect Docker logs and restore the matching backup in an isolated project before deciding recovery.')
        }
        throw
    } finally { Remove-Item -LiteralPath $mutex -Force -ErrorAction SilentlyContinue }
}
function Usage {
@'
FrappeUp CLI
Usage:
  frappeup init --profile development|production [--env-file PATH]
  frappeup catalog list
  frappeup plan --env-file PATH
  frappeup lock --env-file PATH
  frappeup workspace --env-file PATH
  frappeup install --env-file PATH [--existing keep]
  frappeup app prepare --current-env-file CURRENT --env-file TARGET
  frappeup app plan --current-env-file CURRENT --env-file TARGET
  frappeup app apply --current-env-file CURRENT --env-file TARGET [--yes]
  frappeup backup --env-file PATH
  frappeup backup verify --backup-dir PATH
  frappeup restore --env-file PROFILE --backup-dir PATH [--yes]
  frappeup credentials --env-file PATH
  frappeup status --env-file PATH
  frappeup logs --env-file PATH [--docker] [--lines N] [--follow]
  frappeup doctor [--env-file PATH]
  frappeup version
'@
}
try {
    if (!$Arguments.Count) { Usage; exit 0 }
    $command=$Arguments[0]
    if ($command -in 'help','--help','-h') { Usage; exit 0 }
    if ($command -in 'version','--version') { $Version; exit 0 }
    if ($command -eq 'catalog') {
        if ($Arguments.Count -ne 2 -or $Arguments[1] -ne 'list') { Fail 'Use catalog list' }
        $catalog=Read-Env $CatalogPath 'catalog'
        foreach ($id in ($catalog['APP_IDS'] -split '\s+')) { "$id`t$($catalog["APP_${id}_DISPLAY_NAME"])`t$($catalog["APP_${id}_REF_KIND"]) @ $($catalog["APP_${id}_REF"])" }
        exit 0
    }
    if ($command -eq 'app') {
        if ($Arguments.Count -lt 2 -or $Arguments[1] -notin 'prepare','plan','apply') { Fail 'Use app prepare, app plan, or app apply' }
        $appOptions=Parse-Options @($Arguments | Select-Object -Skip 2)
        if ($Arguments[1] -eq 'prepare') { App-Prepare $appOptions; exit 0 }
        if ($Arguments[1] -eq 'plan') { App-Plan $appOptions; exit 0 }
        App-Apply $appOptions; exit 0
    }
    if ($command -eq 'backup' -and $Arguments.Count -ge 2 -and $Arguments[1] -eq 'verify') {
        $verifyOptions=Parse-Options @($Arguments | Select-Object -Skip 2)
        Verify-Backup $verifyOptions['--backup-dir']; exit 0
    }
    $opts=Parse-Options @($Arguments | Select-Object -Skip 1)
    if ($command -eq 'init') {
        $selected=if ($opts['--profile']) { $opts['--profile'] } else { 'development' }
        if ($selected -notin 'development','production') { Fail 'Invalid profile' }
        $path=if ($opts['--env-file']) { $opts['--env-file'] } else { "frappeup.$selected.env" }
        if ((Test-Path $path) -and !$opts['--force']) { Fail "$path exists; use --force" }
        $project=if ($selected -eq 'development') { 'frappeup-dev' } else { 'frappeup-prod' }
        $site=if ($selected -eq 'development') { 'site.localhost' } else { 'site.example.com' }
        $profile=@{PROFILE=$selected; PROJECT_NAME=$project; SITE_NAME=$site; FRAPPE_REPOSITORY='https://github.com/frappe/frappe'; FRAPPE_REF='version-16'; FRAPPE_REF_KIND='branch'; FRAPPE_DOCKER_REPOSITORY='https://github.com/frappe/frappe_docker'; FRAPPE_DOCKER_REF='main'; FRAPPE_DOCKER_REF_KIND='branch'; FRAPPE_MAJOR='16'; INSTALL_APPS='erpnext'}
        Write-Env $path $profile; "Created $path"; exit 0
    }
    Load-Profile $opts
    if ($command -eq 'credentials') {
        $path=Join-Path $WorkspacePath 'credentials.env'
        $credentials=Read-Env $path
        $password=Get-Val $credentials 'ADMIN_PASSWORD'
        if (!$password) { Fail 'Initial Administrator password is missing' }
        "Login: Administrator`nInitial password: $password"; exit 0
    }
    if ($command -eq 'backup') { Doctor | Out-Null; Backup-Site $WorkspacePath 'manual'; Log "backup.completed $($Profile['PROJECT_NAME']) $BackupDir"; "Backup: $BackupDir"; exit 0 }
    if ($command -eq 'restore') { Restore-Site $opts; exit 0 }
    if ($command -eq 'doctor') { Doctor; Log 'doctor.completed'; exit 0 }
    if ($command -eq 'status') { Run docker (@('compose')+(Compose-Args)+@('ps')); exit 0 }
    if ($command -eq 'logs') {
        $lines=if ($opts['--lines']) { $opts['--lines'] } else { '100' }
        if ($lines -notmatch '^[0-9]+$') { Fail 'Invalid --lines' }
        if ($opts['--docker']) { $a=@('compose')+(Compose-Args)+@('logs','--tail',$lines); if ($opts['--follow']) { $a+='--follow' }; Run docker $a }
        else { $path=Join-Path $LogDir 'cli.log'; if (Test-Path $path) { Get-Content $path -Tail ([int]$lines) -Wait:([bool]$opts['--follow']) } }
        exit 0
    }
    if ($command -in 'plan','lock','workspace') { Build-Plan }
    if ($command -eq 'plan') {
        "Profile: $($Profile['PROFILE'])`nProject: $($Profile['PROJECT_NAME'])`nSite: $($Profile['SITE_NAME'])`nFrappe: $($Profile['FRAPPE_REPOSITORY']) @ $($Profile['FRAPPE_REF'])`nFrappe Docker: $($Profile['FRAPPE_DOCKER_REPOSITORY']) @ $($Profile['FRAPPE_DOCKER_REF'])`nApps (install order):"
        foreach ($id in $Apps) { "  - $id [$(App-Kind $id)] @ $(App-Ref $id)" }; exit 0
    }
    if ($command -eq 'lock') {
        $path=if ($opts['--output']) { $opts['--output'] } else { "$EnvPath.lock.env" }
        if ((Test-Path $path) -and !$opts['--force']) { Fail "$path exists; use --force" }
        $lock=@{LOCK_SCHEMA='2'; LOCK_PLAN_SHA256=(Plan-Hash); LOCK_PROJECT_NAME=$Profile['PROJECT_NAME']; LOCK_SITE_NAME=$Profile['SITE_NAME']; LOCK_FRAPPE_REPOSITORY=$Profile['FRAPPE_REPOSITORY']; LOCK_FRAPPE_REF=$Profile['FRAPPE_REF']; LOCK_FRAPPE_REF_KIND=$Profile['FRAPPE_REF_KIND']; LOCK_FRAPPE_DOCKER_REPOSITORY=$Profile['FRAPPE_DOCKER_REPOSITORY']; LOCK_FRAPPE_DOCKER_REF=$Profile['FRAPPE_DOCKER_REF']; LOCK_FRAPPE_DOCKER_REF_KIND=$Profile['FRAPPE_DOCKER_REF_KIND']; LOCK_APP_IDS=($Apps -join ' ')}
        $lock['LOCK_FRAPPE_COMMIT']=Resolve-Commit $Profile['FRAPPE_REPOSITORY'] $Profile['FRAPPE_REF'] $Profile['FRAPPE_REF_KIND']
        $lock['LOCK_FRAPPE_DOCKER_COMMIT']=Resolve-Commit $Profile['FRAPPE_DOCKER_REPOSITORY'] $Profile['FRAPPE_DOCKER_REF'] $Profile['FRAPPE_DOCKER_REF_KIND']
        foreach ($id in $Apps) { $lock["LOCK_APP_${id}_REPOSITORY"]=App-Field $id 'REPOSITORY'; $lock["LOCK_APP_${id}_REF"]=App-Ref $id; $lock["LOCK_APP_${id}_REF_KIND"]=App-Kind $id; $lock["LOCK_APP_${id}_APP_NAME"]=App-Field $id 'APP_NAME'; $lock["LOCK_APP_${id}_COMMIT"]=Resolve-Commit (App-Field $id 'REPOSITORY') (App-Ref $id) (App-Kind $id) }
        Write-Env $path $lock; Log 'lock.completed'; "Created $path"; exit 0
    }
    if ($command -eq 'workspace') {
        Load-Lock $opts
        if (Test-Path $WorkspacePath) {
            if (!$opts['--force']) { Fail 'Workspace exists; use --force' }
            $containers=& docker ps -aq --filter "label=com.docker.compose.project=$($Profile['PROJECT_NAME'])"
            $volumes=& docker volume ls -q --filter "label=com.docker.compose.project=$($Profile['PROJECT_NAME'])"
            if ($containers -or $volumes) { Fail 'Docker project still has resources; refusing to replace its workspace' }
            Remove-Item $WorkspacePath -Recurse -Force
        }
        $temporary="$WorkspacePath.tmp.$PID"
        New-Item -ItemType Directory -Force -Path $temporary | Out-Null
        try {
            Snapshot $Lock['LOCK_FRAPPE_DOCKER_REPOSITORY'] $Lock['LOCK_FRAPPE_DOCKER_COMMIT'] (Join-Path $temporary 'runtime')
            $sources=Join-Path $temporary 'runtime/sources'
            New-Item -ItemType Directory -Force -Path (Join-Path $sources 'apps') | Out-Null
            Snapshot $Lock['LOCK_FRAPPE_REPOSITORY'] $Lock['LOCK_FRAPPE_COMMIT'] (Join-Path $sources 'frappe')
            foreach ($id in $Apps) { Snapshot $Lock["LOCK_APP_${id}_REPOSITORY"] $Lock["LOCK_APP_${id}_COMMIT"] (Join-Path $sources "apps/$id") }
            $containerfile=Join-Path $temporary 'runtime/images/custom/Containerfile'
            $content=[IO.File]::ReadAllText($containerfile)
            if (($content.Split([string[]]@('ARG FRAPPE_BRANCH='),[StringSplitOptions]::None).Count -ne 2) -or ($content.Split([string[]]@('ARG FRAPPE_PATH='),[StringSplitOptions]::None).Count -ne 2)) { Fail 'Unsupported Frappe Docker Containerfile' }
            $content=$content.Replace("USER frappe`n`nARG FRAPPE_BRANCH=","USER frappe`n`nCOPY --chown=frappe:0 sources /opt/frappe/sources`n`nARG FRAPPE_BRANCH=")
            $content=[regex]::Replace($content,'(?m)^ARG FRAPPE_BRANCH=.*$','ARG FRAPPE_BRANCH=frappeup-lock')
            $content=[regex]::Replace($content,'(?m)^ARG FRAPPE_PATH=.*$','ARG FRAPPE_PATH=file:///opt/frappe/sources/frappe')
            [IO.File]::WriteAllText($containerfile,$content)
            $appSources=@(foreach ($id in $Apps) { @{url="file:///opt/frappe/sources/apps/$id"; branch='frappeup-lock'} })
            [IO.File]::WriteAllText((Join-Path $temporary 'runtime/apps.json'),(ConvertTo-Json -InputObject $appSources -Depth 4))
            $random=[byte[]]::new(32); [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($random); $admin=[Convert]::ToBase64String($random)
            [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($random); $db=[Convert]::ToBase64String($random)
            Write-Env (Join-Path $temporary 'credentials.env') @{ADMIN_PASSWORD=$admin; DB_PASSWORD=$db}
            Write-Env (Join-Path $temporary 'workspace.env') @{WORKSPACE_PLAN_SHA256=$Lock['LOCK_PLAN_SHA256']; IMAGE="frappeup/$($Profile['PROJECT_NAME'])"; TAG=$Lock['LOCK_PLAN_SHA256'].Substring(0,12)}
            Move-Item $temporary $WorkspacePath
        } finally { if (Test-Path $temporary) { Remove-Item $temporary -Recurse -Force } }
        Log 'workspace.completed'; "Created workspace $WorkspacePath"; exit 0
    }
    if ($command -eq 'install') {
        if ($Profile['PROFILE'] -ne 'development') { Fail 'Production installation is not implemented yet' }
        Doctor
        $existing=Project-Resources
        if ($existing -and !(Choose-Existing $opts)) { exit 0 }
        if (!$existing -and $opts['--existing'] -and $opts['--existing'] -ne 'keep') { Fail '--existing supports keep only' }
        Build-Plan
        Load-Lock $opts
        $runtime=Join-Path $WorkspacePath 'runtime'
        foreach ($needed in @((Join-Path $runtime 'images/custom/Containerfile'),(Join-Path $runtime 'apps.json'),(Join-Path $WorkspacePath 'credentials.env'),(Join-Path $WorkspacePath 'workspace.env'))) { if (!(Test-Path $needed)) { Fail 'Workspace is incomplete; run workspace first' } }
        $meta=Read-Env (Join-Path $WorkspacePath 'workspace.env') 'workspace'
        if ($meta['WORKSPACE_PLAN_SHA256'] -ne $Lock['LOCK_PLAN_SHA256']) { Fail 'Workspace does not match lock' }
        $image="frappeup/$($Profile['PROJECT_NAME'])"; $tag=$Lock['LOCK_PLAN_SHA256'].Substring(0,12)
        Run docker @('buildx','build','--platform','linux/amd64','--load','--tag',"${image}:$tag",'--file',(Join-Path $runtime 'images/custom/Containerfile'),'--secret',"id=apps_json,src=$(Join-Path $runtime 'apps.json')",$runtime)
        Write-Env (Join-Path $runtime '.frappeup.env') @{CUSTOM_IMAGE=$image; CUSTOM_TAG=$tag; PULL_POLICY='never'; FRAPPE_SITE_NAME_HEADER=$Profile['SITE_NAME']}
        $site=$Profile['SITE_NAME']; $script='set -e; wait-for-it db:3306 -t 120; bench new-site --mariadb-user-host-login-scope=% --admin-password=$$ADMIN_PASSWORD --db-root-username=root --db-root-password=$$DB_PASSWORD --set-default ' + $site + ';'
        foreach ($id in $Apps) { $script += " bench --site $site install-app $(App-Field $id 'APP_NAME');" }
        $yaml=@'
services:
  create-site:
    image: ${CUSTOM_IMAGE}:${CUSTOM_TAG}
    platform: linux/amd64
    pull_policy: never
    restart: "no"
    volumes:
      - sites:/home/frappe/frappe-bench/sites
    depends_on:
      configurator:
        condition: service_completed_successfully
      db:
        condition: service_healthy
    environment:
      ADMIN_PASSWORD: ${ADMIN_PASSWORD}
      DB_PASSWORD: ${DB_PASSWORD}
    entrypoint: ["bash", "-c"]
    command: [__SCRIPT__]
'@
        $yaml=$yaml.Replace('__SCRIPT__',($script | ConvertTo-Json -Compress))
        [IO.File]::WriteAllText((Join-Path $runtime 'frappeup.create-site.yaml'),$yaml)
        $compose=Compose-Args
        Run docker (@('compose')+$compose+@('config','-q'))
        if ($existing -and !(Reset-Project)) { exit 0 }
        Run docker (@('compose')+$compose+@('up','-d'))
        Run docker (@('compose')+$compose+@('wait','create-site'))
        if (!(Existing-Site)) { Fail 'Site task finished but site is unavailable' }
        Log 'install.completed'; "Installed $site`nSign in as Administrator. Get the initial password with: frappeup credentials --env-file $EnvPath"; exit 0
    }
    Fail "Unknown command $command"
} catch { [Console]::Error.WriteLine("error: $($_.Exception.Message)"); exit 1 }
