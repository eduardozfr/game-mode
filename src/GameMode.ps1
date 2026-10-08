#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Monitor','Restore','Status','Validate')]
    [string]$Action = 'Monitor'
)

$ErrorActionPreference = 'Stop'
$script:Root = Split-Path -Parent $PSScriptRoot
$script:Data = Join-Path $script:Root 'data'
$script:StateFile = Join-Path $script:Data 'state.json'
$script:StopFlag = Join-Path $script:Data 'stop.signal'
$script:LogFile = Join-Path $script:Data 'game-mode.log'
$script:TaskName = 'PersonalGameModeV7'
$script:PlanHigh = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
$script:AllowedServices = @('Spooler','WSearch')
# Validacao fechada: perfis JSON nao podem apontar para componentes arbitrarios do sistema.
$script:AllowedApps = @(
    'chrome','msedge','firefox','brave','opera','opera_gx','cursor','code','node',
    'spotify','onedrive','nextcloud','icloudhome','iclouddrive','icloudphotos',
    'rustdesk','mobaxterm','widgets','phoneexperiencehost','yourphone',
    'docker desktop','com.docker.backend','teams','ms-teams','telegram','whatsapp'
)
$script:ProtectedProcesses = @(
    'steam','steamwebhelper','cs2','rdr2','flightsimulator2024',
    'lghub','lghub_agent','lghub_updater','nvcontainer','nvidia share',
    'dwm','explorer','winlogon','csrss','services','lsass','svchost',
    'audiodg','igoSwServer','powershell','pwsh','gamebar','gamingservices',
    'rockstarservice','launcher','socialclubhelper','awcc','awccservice',
    'alienwarecommandcenter'
)

if (!(Test-Path -LiteralPath $script:Data)) {
    New-Item -ItemType Directory -Path $script:Data -Force | Out-Null
}

function Log([string]$Message,[string]$Level='INFO') {
    $entry = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try { Add-Content -LiteralPath $script:LogFile -Value $entry -Encoding UTF8 } catch {}
    if ($Action -ne 'Monitor') { Write-Host $entry }
}
function Get-Settings {
    $path = Join-Path $script:Root 'config.json'
    $cfg = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    $s = [int]$cfg.pollSeconds
    if ($s -lt 2 -or $s -gt 15) { throw 'pollSeconds deve estar entre 2 e 15.' }
    $g = [int]$cfg.exitGraceSeconds
    if ($g -lt 5 -or $g -gt 120) { throw 'exitGraceSeconds deve estar entre 5 e 120.' }
    return $cfg
}
function Get-Profiles {
    $result = @()
    foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $script:Root 'profiles') -Filter '*.json' -File | Sort-Object Name)) {
        $p = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($p.enabled -eq $false) { continue }
        if ($p.id -notmatch '^[a-z0-9-]{2,40}$') { throw "ID de perfil invalido em $($file.Name)" }
        if ($p.processName -notmatch '^[A-Za-z0-9_\-]{2,64}$') { throw "Nome de processo invalido em $($file.Name)" }
        if ($p.processName.ToLowerInvariant() -in @('svchost','explorer','winlogon','services','lsass','dwm')) {
            throw "Processo protegido no perfil $($file.Name)"
        }
        foreach ($svc in @($p.stopServices)) {
            if ($svc -notin $script:AllowedServices) { throw "Servico nao autorizado ($svc) no perfil $($file.Name)" }
        }
        foreach ($item in @($p.closeApps)) {
            $name = [string]$item.name
            if ($name.ToLowerInvariant() -notin $script:AllowedApps -or $name.ToLowerInvariant() -in $script:ProtectedProcesses) {
                throw "Aplicativo nao autorizado ($name) no perfil $($file.Name)"
            }
            if ($item.mode -notin @('graceful','force')) { throw "Modo de fechamento invalido para $name" }
        }
        $result += $p
    }
    if ($result.Count -eq 0) { throw 'Nenhum perfil ativo encontrado.' }
    if (@($result | Select-Object -ExpandProperty id -Unique).Count -ne $result.Count) { throw 'IDs de perfis repetidos.' }
    return @($result)
}
function Save-State($value) {
    $temp = $script:StateFile + '.tmp'
    ConvertTo-Json -InputObject $value -Depth 12 | Set-Content -LiteralPath $temp -Encoding UTF8
    Move-Item -LiteralPath $temp -Destination $script:StateFile -Force
}
function Read-State {
    if (!(Test-Path -LiteralPath $script:StateFile)) { return $null }
    return Get-Content -LiteralPath $script:StateFile -Raw -Encoding UTF8 | ConvertFrom-Json
}
function Get-CurrentPowerPlan {
    try {
        $output = (& powercfg.exe /getactivescheme 2>&1 | Out-String)
        if ($LASTEXITCODE -eq 0 -and $output -match '([A-Fa-f0-9]{8}(?:-[A-Fa-f0-9]{4}){3}-[A-Fa-f0-9]{12})') { return $Matches[1] }
    } catch { Log "Nao foi possivel consultar plano de energia: $_" 'WARN' }
    return $null
}
function Snapshot-Registry([string]$Path,[string]$Name,[int]$Value) {
    $exists = $false; $old = $null
    if (Test-Path -LiteralPath $Path) {
        try {
            $key = Get-Item -LiteralPath $Path
            if ($key.GetValueNames() -contains $Name) {
                $exists = $true
                $old = $key.GetValue($Name)
            }
        } catch { Log "Registro original inacessivel: $Path/$Name" 'WARN' }
    }
    return [ordered]@{ path=$Path; name=$Name; existed=$exists; value=$old; target=$Value }
}
function Get-RegistryChanges {
    return @(
        (Snapshot-Registry 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1),
        (Snapshot-Registry 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0),
        (Snapshot-Registry 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0)
    )
}
function Set-GameRegistry($items) {
    foreach ($item in @($items)) {
        try {
            if (!(Test-Path -LiteralPath $item.path)) { New-Item -Path $item.path -Force | Out-Null }
            New-ItemProperty -Path $item.path -Name $item.name -PropertyType DWord -Value ([int]$item.target) -Force | Out-Null
        } catch { Log "Falha ao definir preferencia $($item.name): $_" 'WARN' }
    }
}
function Restore-GameRegistry($items) {
    foreach ($item in @($items)) {
        try {
            if ($item.existed) {
                if (!(Test-Path -LiteralPath $item.path)) { New-Item -Path $item.path -Force | Out-Null }
                New-ItemProperty -Path $item.path -Name $item.name -PropertyType DWord -Value ([int]$item.value) -Force | Out-Null
            } elseif (Test-Path -LiteralPath $item.path) {
                Remove-ItemProperty -Path $item.path -Name $item.name -ErrorAction SilentlyContinue
            }
        } catch { Log "Nao foi possivel restaurar $($item.name): $_" 'ERROR'; $script:RestoreErrors++ }
    }
}
function Snapshot-Services($services) {
    $state = @()
    foreach ($name in @($services | Select-Object -Unique)) {
        if ($name -notin $script:AllowedServices) { continue }
        $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($null -eq $svc) { continue }
        $state += [ordered]@{ name=$name; wasRunning=($svc.Status -eq 'Running') }
    }
    return @($state)
}
function Stop-SelectedServices($states) {
    foreach ($item in @($states)) {
        if (!$item.wasRunning) { continue }
        try {
            $service = Get-Service -Name $item.name -ErrorAction Stop
            if (@($service.DependentServices | Where-Object { $_.Status -eq 'Running' }).Count -gt 0) {
                Log "Servico $($item.name) tem dependencias ativas; preservado." 'WARN'
                continue
            }
            Stop-Service -Name $item.name -ErrorAction Stop
            Log "Servico opcional pausado: $($item.name)"
        } catch { Log "Servico $($item.name) preservado (falha/permissao): $_" 'WARN' }
    }
}
function Restore-Services($states) {
    foreach ($item in @($states)) {
        if (!$item.wasRunning -or $item.name -notin $script:AllowedServices) { continue }
        try {
            $svc = Get-Service -Name $item.name -ErrorAction Stop
            if ($svc.Status -ne 'Running') {
                Start-Service -Name $item.name -ErrorAction Stop
                Log "Servico restaurado: $($item.name)"
            }
        } catch { Log "Falha restaurando servico $($item.name): $_" 'ERROR'; $script:RestoreErrors++ }
    }
}
function Close-KnownApps($profile) {
    foreach ($app in @($profile.closeApps)) {
        $name = [string]$app.name
        if ($name.ToLowerInvariant() -notin $script:AllowedApps -or $name.ToLowerInvariant() -in $script:ProtectedProcesses) { continue }
        foreach ($proc in @(Get-Process -Name $name -ErrorAction SilentlyContinue)) {
            try {
                if ([int]$proc.Id -eq $PID) { continue }
                if ($app.mode -eq 'graceful') {
                    if ($proc.MainWindowHandle -eq [IntPtr]::Zero) { continue }
                    [void]$proc.CloseMainWindow()
                    Log "Fechamento solicitado: $name (PID $($proc.Id))"
                } else {
                    Stop-Process -Id $proc.Id -Force -ErrorAction Stop
                    Log "Aplicativo autorizado encerrado: $name (PID $($proc.Id))"
                }
            } catch { Log "Falha encerrando $name: $_" 'WARN' }
        }
    }
    if ($profile.stopWSL -eq $true) {
        try {
            $vm = @(Get-Process -Name 'vmmemWSL','vmmem' -ErrorAction SilentlyContinue)
            if ($vm.Count -gt 0 -and (Get-Command 'wsl.exe' -ErrorAction SilentlyContinue)) {
                & wsl.exe --shutdown 2>&1 | Out-Null
                Log 'WSL interrompido conforme perfil. Sessoes WSL nao serao reabertas.'
            }
        } catch { Log "WSL preservado: $_" 'WARN' }
    }
}
function Apply-GamePriority($profile) {
    foreach ($proc in @(Get-Process -Name $profile.processName -ErrorAction SilentlyContinue)) {
        try {
            $state = Read-State
            if ($null -eq $state) { continue }
            $known = @($state.priorities | Where-Object { $_.pid -eq $proc.Id })
            if ($known.Count -eq 0) {
                $snapshot = [ordered]@{
                    pid=[int]$proc.Id
                    startTime=$proc.StartTime.ToUniversalTime().ToString('o')
                    original=[string]$proc.PriorityClass
                }
                # Salvar o valor antigo antes de mudar a prioridade.
                $state.priorities = @($state.priorities) + @($snapshot)
                Save-State $state
            }
            if ($proc.PriorityClass -ne 'AboveNormal') {
                $proc.PriorityClass = 'AboveNormal'
                Log "Prioridade AboveNormal: $($profile.processName) PID $($proc.Id)"
            }
        } catch { Log "Prioridade nao alterada para $($profile.processName): $_" 'WARN' }
    }
}
function Restore-Priorities($items) {
    foreach ($item in @($items)) {
        try {
            $proc = Get-Process -Id ([int]$item.pid) -ErrorAction SilentlyContinue
            if ($null -eq $proc) { continue }
            if ($proc.StartTime.ToUniversalTime().ToString('o') -ne [string]$item.startTime) { continue }
            $proc.PriorityClass = [System.Diagnostics.ProcessPriorityClass]([string]$item.original)
            Log "Prioridade restaurada: PID $($proc.Id)"
        } catch { Log "Falha ao restaurar prioridade PID $($item.pid): $_" 'WARN' }
    }
}
function Start-Profile($profile, $settings) {
    if (Read-State) { throw 'Estado anterior pendente: execute a restauracao antes de otimizar.' }
    $oldPlan = Get-CurrentPowerPlan
    $services = Snapshot-Services $profile.stopServices
    $snapshot = [ordered]@{
        version=7; id=[string]$profile.id; started=(Get-Date).ToString('o')
        oldPlan=$oldPlan; selectedPlan=$null
        registry=@(Get-RegistryChanges); services=@($services); priorities=@()
    }
    # Salva ANTES da primeira mudanca, para recuperar ate apos queda de energia.
    Save-State $snapshot
    Log "Perfil iniciado: $($profile.displayName)"
    Set-GameRegistry $snapshot.registry
    if ($settings.useHighPerformancePlan -eq $true -and $oldPlan -and $oldPlan -ne $script:PlanHigh) {
        try {
            $output = (& powercfg.exe /setactive $script:PlanHigh 2>&1 | Out-String)
            if ($LASTEXITCODE -eq 0) {
                Log 'Plano de alto desempenho ativado temporariamente.'
            } else { Log "Plano alto desempenho indisponivel: $output" 'WARN' }
        } catch { Log "Plano de energia nao alterado: $_" 'WARN' }
    }
    Close-KnownApps $profile
    Stop-SelectedServices $services
    Apply-GamePriority $profile
}
function Restore-Session {
    $state = $null
    try { $state = Read-State }
    catch { Log "Estado invalido; preserve data/state.json para recuperacao manual: $_" 'ERROR'; return $false }
    if ($null -eq $state) { return $true }
    $script:RestoreErrors = 0
    Log "Restaurando perfil $($state.id)..."
    Restore-GameRegistry $state.registry
    Restore-Priorities $state.priorities
    Restore-Services $state.services
    if ($state.oldPlan) {
        try {
            $current = Get-CurrentPowerPlan
            if ($current -and $current -ne $state.oldPlan) {
                & powercfg.exe /setactive $state.oldPlan 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) { throw "powercfg exit=$LASTEXITCODE" }
                Log "Plano anterior restaurado: $($state.oldPlan)"
            }
        } catch { Log "Plano nao restaurado: $_" 'ERROR'; $script:RestoreErrors++ }
    }
    if ($script:RestoreErrors -eq 0) {
        Remove-Item -LiteralPath $script:StateFile -Force -ErrorAction SilentlyContinue
        Log 'Restauracao concluida. Aplicativos encerrados nao sao reabertos.'
        return $true
    }
    Log 'Restauracao parcial; state.json preservado para nova tentativa.' 'WARN'
    return $false
}
function Active-Profile($profiles) {
    foreach ($profile in @($profiles)) {
        if (@(Get-Process -Name $profile.processName -ErrorAction SilentlyContinue).Count -gt 0) { return $profile }
    }
    return $null
}
function Stop-Requested { return (Test-Path -LiteralPath $script:StopFlag) }
function Run-Monitor {
    $cfg = Get-Settings
    $profiles = @(Get-Profiles)
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value.Replace('-','_')
    $lock = New-Object System.Threading.Mutex($false, ('Local\PersonalGameModeV7_' + $sid))
    $haveLock = $false
    try {
        $haveLock = $lock.WaitOne(0)
        if (!$haveLock) { Log 'Monitor ja em execucao; encerrando duplicata.'; return }
        Remove-Item -LiteralPath $script:StopFlag -Force -ErrorAction SilentlyContinue
        if (!(Restore-Session)) { Log 'Recuperacao incompleta; monitor nao iniciara.' 'ERROR'; return }
        Log "Monitor automatico iniciado: $($profiles.Count) perfil(is), intervalo $($cfg.pollSeconds)s."
        $activeId = $null
        $lastSeen = Get-Date
        while (!(Stop-Requested)) {
            try {
                $detected = Active-Profile $profiles
                if ($null -eq $activeId) {
                    if ($null -ne $detected) {
                        Start-Profile $detected $cfg
                        $activeId = $detected.id
                        $lastSeen = Get-Date
                    }
                } else {
                    $currentProfile = @($profiles | Where-Object { $_.id -eq $activeId })[0]
                    $stillRunning = @(Get-Process -Name $currentProfile.processName -ErrorAction SilentlyContinue).Count -gt 0
                    if ($stillRunning) {
                        $lastSeen = Get-Date
                        Apply-GamePriority $currentProfile
                    } elseif (((Get-Date) - $lastSeen).TotalSeconds -ge [int]$cfg.exitGraceSeconds) {
                        if (Restore-Session) { $activeId = $null }
                    }
                }
            } catch { Log "Erro no ciclo de monitoramento: $_" 'ERROR' }
            Start-Sleep -Seconds ([int]$cfg.pollSeconds)
        }
    } finally {
        if ($haveLock) {
            [void](Restore-Session)
            [void]$lock.ReleaseMutex()
        }
        $lock.Dispose()
        Log 'Monitor encerrado.'
    }
}

switch ($Action) {
    'Monitor'  { Run-Monitor }
    'Restore'  {
        # Solicite primeiro a parada do monitor com RESTAURAR.cmd; evite corridas.
        if (!(Restore-Session)) { exit 2 }
    }
    'Status'   {
        $state = Read-State
        if ($state) { Write-Host "Perfil ativo/pendente: $($state.id) desde $($state.started)" }
        else { Write-Host 'Nenhum perfil ativo ou restauracao pendente.' }
        try {
            $task = Get-ScheduledTask -TaskName $script:TaskName -ErrorAction Stop
            Write-Host "Agendamento: $($task.State)"
        } catch { Write-Host 'Agendamento: nao instalado.' }
        if (Test-Path -LiteralPath $script:LogFile) {
            Write-Host 'Ultimas linhas do log:'
            Get-Content -LiteralPath $script:LogFile -Tail 12
        }
    }
    'Validate' {
        [void](Get-Settings)
        $profiles = @(Get-Profiles)
        Write-Host "OK: $($profiles.Count) perfis validados."
        foreach ($p in $profiles) { Write-Host " - $($p.id): $($p.processName)" }
    }
}