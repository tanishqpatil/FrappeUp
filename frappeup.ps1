$Arguments = @($args)
$ErrorActionPreference = 'Stop'
$ScriptRoot = Split-Path -Parent $PSCommandPath
if (Test-Path (Join-Path $ScriptRoot 'catalog\official-apps.env')) { $Root = $ScriptRoot } else { $Root = Split-Path -Parent $ScriptRoot }
$CatalogPath = Join-Path $Root 'catalog\official-apps.env'
$Version = '0.3.1'

function Fail([string]$Message) { throw $Message }
function Read-Env([string]$Path) {
    if (!(Test-Path $Path)) { Fail "Cannot read $Path" }
    $map = @{}
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        $line = $line.Trim()
        if (!$line -or $line.StartsWith('#')) { continue }
        if ($line -notmatch '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') { Fail "Invalid KEY=VALUE line in $Path" }
        $value = $Matches[2].Trim()
        if ($value.Length -ge 2 -and $value.StartsWith("'") -and $value.EndsWith("'")) { $value = $value.Substring(1,$value.Length-2).Replace("'\''", "'") }
        elseif ($value.Length -ge 2 -and $value.StartsWith('"') -and $value.EndsWith('"')) { $value = $value.Substring(1,$value.Length-2) }
        $map[$Matches[1]] = $value
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
            {$_ -in '--force','--docker','--follow'} { $options[$name]=$true; break }
            {$_ -in '--profile','--env-file','--lock-file','--output','--lines','--existing'} {
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
    $script:Profile=Read-Env $EnvPath
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
    if ($Profile['PROFILE'] -notin 'development','production') { Fail 'PROFILE must be development or production' }
    if ($Profile['PROJECT_NAME'] -notmatch '^[A-Za-z0-9_-]+$') { Fail 'Invalid PROJECT_NAME' }
    if ($Profile['SITE_NAME'] -notmatch '^[A-Za-z0-9.-]+$') { Fail 'Invalid SITE_NAME' }
    if ($Profile['FRAPPE_MAJOR'] -notmatch '^[1-9][0-9]*$') { Fail 'Invalid FRAPPE_MAJOR' }
    $envDir=Split-Path -Parent $EnvPath
    $legacyWorkspace=Join-Path $envDir ".frappe1tap/workspaces/$($Profile['PROJECT_NAME'])"
    $workspace=Get-Val $Profile 'WORKSPACE_DIR' $(if (Test-Path $legacyWorkspace) { ".frappe1tap/workspaces/$($Profile['PROJECT_NAME'])" } else { ".frappeup/workspaces/$($Profile['PROJECT_NAME'])" })
    $script:WorkspacePath=[IO.Path]::GetFullPath((Join-Path $envDir $workspace))
    $script:LogDir=Join-Path $envDir $(if ($WorkspacePath -like '*.frappe1tap\workspaces\*') { '.frappe1tap/logs' } else { '.frappeup/logs' })
    $script:Catalog=Read-Env $CatalogPath
    $custom=Get-Val $Profile 'CUSTOM_APPS_FILE'
    if ($custom) {
        $customPath=[IO.Path]::GetFullPath((Join-Path $envDir $custom))
        $extra=Read-Env $customPath
        foreach ($key in $extra.Keys) { $Catalog[$key]=$extra[$key] }
        $Catalog['APP_IDS'] += ' ' + (Get-Val $extra 'CUSTOM_APP_IDS')
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
    $script:Lock=Read-Env $LockPath
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
function Compose-Args {
    $runtime=Join-Path $WorkspacePath 'runtime'
    $runtimeEnv=if (Test-Path (Join-Path $runtime '.frappeup.env')) { Join-Path $runtime '.frappeup.env' } else { Join-Path $runtime '.frappe1tap.env' }
    $siteCompose=if (Test-Path (Join-Path $runtime 'frappeup.create-site.yaml')) { Join-Path $runtime 'frappeup.create-site.yaml' } else { Join-Path $runtime 'frappe1tap.create-site.yaml' }
    return @('--env-file',$runtimeEnv,'--env-file',(Join-Path $WorkspacePath 'credentials.env'),'-p',$Profile['PROJECT_NAME'],'-f',(Join-Path $runtime 'compose.yaml'),'-f',(Join-Path $runtime 'overrides/compose.mariadb.yaml'),'-f',(Join-Path $runtime 'overrides/compose.redis.yaml'),'-f',(Join-Path $runtime 'overrides/compose.noproxy.yaml'),'-f',$siteCompose)
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
function Backup-Before-Reset {
    $compose=Compose-Args
    $backend=& docker compose @compose ps -q backend 2>$null
    if ($LASTEXITCODE -ne 0 -or !$backend) { Fail 'Reset requires a running backend to create a verified backup; no data was changed' }
    & docker compose @compose exec -T backend bench --site $Profile['SITE_NAME'] list-apps *> $null
    if ($LASTEXITCODE -ne 0) { Fail 'Site is unavailable for backup; no data was changed' }
    $stamp=(Get-Date).ToUniversalTime().ToString('yyyyMMdd_HHmmss')
    $envDir=Split-Path -Parent $EnvPath
    $script:BackupDir=Join-Path $envDir ".frappeup/backups/$($Profile['PROJECT_NAME'])/$stamp-$PID"
    # Frappe expects private/backups to contain files only.
    $containerBackup="/home/frappe/frappe-bench/sites/.frappeup-backups/$($Profile['SITE_NAME'])/reset-$stamp-$PID"
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
    Write-Host "Validated backup archives: $BackupDir"
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
        $catalog=Read-Env $CatalogPath
        foreach ($id in ($catalog['APP_IDS'] -split '\s+')) { "$id`t$($catalog["APP_${id}_DISPLAY_NAME"])`t$($catalog["APP_${id}_REF_KIND"]) @ $($catalog["APP_${id}_REF"])" }
        exit 0
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
        $meta=Read-Env (Join-Path $WorkspacePath 'workspace.env')
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
