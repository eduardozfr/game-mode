#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Monitor','Restore','Status','Validate','Scan')]
    [string]$Action = 'Monitor'
)

$ErrorActionPreference = 'Stop'
$script:Root = Split-Path -Parent $PSScriptRoot
$script:Data = Join-Path $script:Root 'data'
$script:StateFile = Join-Path $script:Data 'state.json'
$script:StopFile = Join-Path $script:Data 'stop.signal'
$script:LogFile = Join-Path $script:Data 'game-mode.log'
$script:HighPlan = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
$script:RestoreFailures = 0
[void](New-Item -ItemType Directory -Path $script:Data -Force -ErrorAction SilentlyContinue)

function Write-Log([string]$Message,[string]$Level='INFO') {
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Level,$Message
    try { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 } catch {}
    if ($Action -ne 'Monitor') { Write-Host $line }
}

function Read-Config {
    $cfg = Get-Content (Join-Path $script:Root 'config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($cfg.schemaVersion -ne 1) { throw 'Formato de configuracao nao suportado.' }
    if ($cfg.autoCloseProcesses -ne $false -or $cfg.stopServices -ne $false) {
        throw 'Esta versao nao admite fechamento automatico de processos ou servicos.'
    }
    if ([int]$cfg.pollIntervalSeconds -lt 3 -or [int]$cfg.pollIntervalSeconds -gt 30) {
        throw 'pollIntervalSeconds precisa estar entre 3 e 30.'
    }
    if ([int]$cfg.exitGraceSeconds -lt 5 -or [int]$cfg.exitGraceSeconds -gt 120) {
        throw 'exitGraceSeconds precisa estar entre 5 e 120.'
    }
    return $cfg
}

function Read-Profiles {
    $result = @()
    foreach ($file in @(Get-ChildItem (Join-Path $script:Root 'profiles') -Filter '*.json' -File)) {
        $p = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($p.enabled -eq $false) { continue }
        if ([string]$p.id -notmatch '^[a-z][a-z0-9-]{1,39}$') { throw "ID invalido em $($file.Name)." }
        if ([string]$p.processName -notmatch '^[A-Za-z0-9_-]{2,64}$') { throw "Processo invalido em $($file.Name)." }
        foreach ($forbidden in @('closeApps','killApps','stopServices','stopWSL','commands')) {
            if ($p.PSObject.Properties.Name -contains $forbidden) { throw "Campo inseguro no perfil $($file.Name): $forbidden" }
        }
        $result += $p
    }
    if ($result.Count -eq 0) { throw 'Nenhum perfil habilitado.' }
    if (@($result | Select-Object -ExpandProperty id -Unique).Count -ne $result.Count) {
        throw 'IDs duplicados nos perfis.'
    }
    return @($result | Sort-Object id)
}

function Read-State {
    if (!(Test-Path -LiteralPath $script:StateFile)) { return $null }
    return (Get-Content -LiteralPath $script:StateFile -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Save-State($Value) {
    $tmp = $script:StateFile + '.tmp'
    ConvertTo-Json -InputObject $Value -Depth 12 |
        Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $script:StateFile -Force
}

function Read-PowerPlan {
    try {
        $out = (& powercfg.exe /getactivescheme 2>&1 | Out-String)
        if ($LASTEXITCODE -eq 0 -and $out -match '([a-fA-F0-9]{8}(?:-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12})') {
            return $Matches[1].ToLowerInvariant()
        }
    } catch { Write-Log "Plano de energia nao identificado: $_" 'WARN' }
    return $null
}

function Snapshot-Registry([string]$Path,[string]$Name,[int]$Target) {
    $exists = $false
    $old = $null
    try {
        if (Test-Path $Path) {
            $key = Get-Item -Path $Path
            if ($key.GetValueNames() -contains $Name) {
                $exists = $true
                $old = [int]$key.GetValue($Name)
            }
        }
    } catch {
        throw "Impossivel capturar valor original de $Name. Nada sera aplicado: $_"
    }
    return [ordered]@{path=$Path;name=$Name;existed=$exists;value=$old;target=$Target}
}

function Get-RegistrySnapshot($cfg) {
    $items = @()
    if ($cfg.applyGameMode) {
        $items += Snapshot-Registry 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1
    }
    if ($cfg.disableBackgroundCapture) {
        $items += Snapshot-Registry 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
        $items += Snapshot-Registry 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0
    }
    return @($items)
}

function Apply-Registry($items) {
    foreach ($item in @($items)) {
        try {
            if (!(Test-Path $item.path)) { [void](New-Item -Path $item.path -Force) }
            [void](New-ItemProperty -Path $item.path -Name $item.name -PropertyType DWord -Value ([int]$item.target) -Force)
        } catch { Write-Log "Registro nao alterado: $($item.name): $_" 'WARN' }
    }
}

function Restore-Registry($items) {
    foreach ($item in @($items)) {
        try {
            if (!(Test-Path $item.path)) { continue }
            $current = (Get-Item -Path $item.path).GetValue([string]$item.name,$null)
            if ($null -eq $current -or [int]$current -ne [int]$item.target) {
                Write-Log "Preferencia $($item.name) mudou externamente; preservada." 'WARN'
                continue
            }
            if ($item.existed) {
                [void](New-ItemProperty -Path $item.path -Name $item.name -PropertyType DWord -Value ([int]$item.value) -Force)
            } else {
                Remove-ItemProperty -Path $item.path -Name $item.name -ErrorAction Stop
            }
        } catch {
            Write-Log "Falha na restauracao de $($item.name): $_" 'ERROR'
            $script:RestoreFailures++
        }
    }
}

function Read-ProcessesByName([string]$Name) {
    return @(Get-Process -Name $Name -ErrorAction SilentlyContinue)
}

function Save-GamePriority($profile) {
    $state = Read-State
    if ($null -eq $state) { return }
    foreach ($proc in @(Read-ProcessesByName $profile.processName)) {
        try {
            if ($proc.PriorityClass -ne [Diagnostics.ProcessPriorityClass]::Normal) { continue }
            $snapshot = [ordered]@{
                pid=[int]$proc.Id
                started=$proc.StartTime.ToUniversalTime().ToString('o')
                original=[string]$proc.PriorityClass
            }
            if (@($state.priorities | Where-Object { $_.pid -eq $proc.Id }).Count -gt 0) { continue }
            $state.priorities = @($state.priorities) + @($snapshot)
            Save-State $state
            $proc.PriorityClass = [Diagnostics.ProcessPriorityClass]::AboveNormal
            Write-Log "Prioridade ajustada para AboveNormal: PID $($proc.Id)"
        } catch { Write-Log "Prioridade preservada: $_" 'WARN' }
    }
}

function Restore-Priorities($items) {
    foreach ($item in @($items)) {
        try {
            $proc = Get-Process -Id ([int]$item.pid) -ErrorAction SilentlyContinue
            if ($null -eq $proc) { continue }
            if ($proc.StartTime.ToUniversalTime().ToString('o') -ne [string]$item.started) { continue }
            if ($proc.PriorityClass -eq [Diagnostics.ProcessPriorityClass]::AboveNormal) {
                $proc.PriorityClass = [Diagnostics.ProcessPriorityClass]::Normal
            }
        } catch {
            Write-Log "Nao foi possivel restaurar prioridade: $_" 'WARN'
        }
    }
}

function Scan-Processes($profile) {
    if ($null -eq $profile) { return }
    try {
        # Apenas leitura: a verificacao de impacto nunca autoriza encerramento.
        $first = @(Get-Process -ErrorAction SilentlyContinue)
        $before = @{}
        foreach ($p in $first) {
            try { $before[[int]$p.Id] = [double]$p.CPU } catch {}
        }
        Start-Sleep -Milliseconds 700
        $later = @(Get-Process -ErrorAction SilentlyContinue)
        $cimMap = @{}
        try {
            foreach ($p in @(Get-CimInstance Win32_Process -ErrorAction Stop)) {
                $cimMap[[int]$p.ProcessId] = $p
            }
        } catch { Write-Log "Metadados CIM indisponiveis: $_" 'WARN' }
        $servicePids = @{}
        try {
            foreach ($svc in @(Get-CimInstance Win32_Service -ErrorAction Stop)) {
                if ([int]$svc.ProcessId -gt 0) { $servicePids[[int]$svc.ProcessId] = $true }
            }
        } catch { Write-Log "Relacionamento de servicos indisponivel: $_" 'WARN' }
        $gameIds = @{}
        foreach ($p in @($later | Where-Object { $_.ProcessName -ieq $profile.processName })) {
            $gameIds[[int]$p.Id] = $true
        }
        $gameRelated = @{}
        foreach ($g in @($gameIds.Keys)) {
            $current = [int]$g
            for ($i=0; $i -lt 25 -and $current -gt 0; $i++) {
                if ($gameRelated.ContainsKey($current)) { break }
                $gameRelated[$current] = $true
                if (!$cimMap.ContainsKey($current)) { break }
                $parent = [int]$cimMap[$current].ParentProcessId
                if ($parent -eq $current) { break }
                $current = $parent
            }
        }
        $result = @()
        foreach ($p in $later) {
            try {
                $pidValue = [int]$p.Id
                $cat = 'protected'
                $reason = 'Dependencia ou natureza desconhecida'
                $meta = $cimMap[$pidValue]
                $fullPath = ''
                if ($meta) { $fullPath = [string]$meta.ExecutablePath }
                if ($gameRelated.ContainsKey($pidValue)) {
                    $cat = 'game-related'; $reason = 'Jogo ou processo ancestral'
                } elseif ($servicePids.ContainsKey($pidValue)) {
                    $reason = 'Hospeda servico Windows'
                } elseif ($fullPath -and $fullPath.StartsWith($env:WINDIR,[StringComparison]::OrdinalIgnoreCase)) {
                    $reason = 'Componente do Windows'
                } elseif ($p.MainWindowHandle -ne [IntPtr]::Zero) {
                    $cat = 'interactive'; $reason = 'Janela de usuario (pode conter dados nao salvos)'
                } elseif ($fullPath -and $p.SessionId -eq (Get-Process -Id $PID).SessionId) {
                    $cat = 'review-only'; $reason = 'Candidato a observacao, sem permissao de fechamento'
                }
                $delta = 0.0
                if ($before.ContainsKey($pidValue)) {
                    $delta = [Math]::Max(0.0,([double]$p.CPU-$before[$pidValue]))
                }
                $result += [ordered]@{
                    pid=$pidValue; name=$p.ProcessName; category=$cat
                    reason=$reason; memoryMB=[Math]::Round($p.WorkingSet64 / 1MB,1)
                    cpuDeltaSeconds=[Math]::Round($delta,3)
                }
            } catch {}
        }
        $file = Join-Path $script:Data ('scan-{0}-{1}.json' -f $profile.id,(Get-Date -Format 'yyyyMMdd-HHmmss'))
        $payload = [ordered]@{
            version='0.1.0';game=$profile.id;capturedAt=(Get-Date).ToString('o')
            warning='Classificacao informativa. Nenhum processo foi encerrado.'
            processes=@($result)
        }
        ConvertTo-Json -InputObject $payload -Depth 6 | Set-Content -LiteralPath $file -Encoding UTF8
        Write-Log ("Scan de processos concluido: {0} processos, {1} para revisao. Nenhum encerramento." -f
            $result.Count,@($result | Where-Object { $_.category -eq 'review-only' }).Count)
    } catch { Write-Log "Falha no scan (jogo preservado): $_" 'WARN' }
}

function Start-Profile($profile,$cfg) {
    if (Read-State) { throw 'Snapshot anterior pendente; restauracao necessaria.' }
    $oldPlan = Read-PowerPlan
    $items = @(Get-RegistrySnapshot $cfg)
    $snapshot = [ordered]@{
        schemaVersion=1;game=$profile.id;startedAt=(Get-Date).ToString('o')
        oldPlan=$oldPlan;plannedHigh=$false
        registry=$items;priorities=@()
    }
    if ($cfg.preferHighPerformancePlan -and $oldPlan -and $oldPlan -ne $script:HighPlan) {
        $available = (& powercfg.exe /list 2>&1 | Out-String)
        if ($LASTEXITCODE -eq 0 -and $available.ToLowerInvariant().Contains($script:HighPlan)) {
            $snapshot.plannedHigh = $true
        }
    }
    Save-State $snapshot
    Write-Log "Jogo detectado: $($profile.name). Snapshot salvo."
    if ($cfg.scanProcessesOnGameStart) { Scan-Processes $profile }
    Apply-Registry $items
    if ($snapshot.plannedHigh) {
        try {
            & powercfg.exe /setactive $script:HighPlan 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { Write-Log 'Alto desempenho habilitado temporariamente.' }
            else { Write-Log 'Plano de alto desempenho indisponivel.' 'WARN' }
        } catch { Write-Log "Plano de energia preservado: $_" 'WARN' }
    }
    if ($cfg.setAboveNormalPriority) { Save-GamePriority $profile }
}

function Restore-Session {
    $state = Read-State
    if ($null -eq $state) { return $true }
    if ($state.schemaVersion -ne 1) {
        Write-Log 'Snapshot incompatível; preservado para revisao manual.' 'ERROR'
        return $false
    }
    $script:RestoreFailures = 0
    Write-Log "Restaurando sessao do jogo $($state.game)"
    Restore-Registry $state.registry
    Restore-Priorities $state.priorities
    if ($state.plannedHigh -and $state.oldPlan) {
        try {
            $current = Read-PowerPlan
            if ($current -eq $script:HighPlan) {
                & powercfg.exe /setactive ([string]$state.oldPlan) 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) { throw "Erro powercfg ($LASTEXITCODE)" }
            } elseif ($null -eq $current) {
                throw 'Plano atual nao pode ser consultado.'
            } else { Write-Log 'Plano alterado por outro aplicativo: preservado.' 'WARN' }
        } catch {
            $script:RestoreFailures++
            Write-Log "Falha ao restaurar energia: $_" 'ERROR'
        }
    }
    if ($script:RestoreFailures -gt 0) {
        Write-Log 'Restauracao incompleta; snapshot mantido.' 'ERROR'
        return $false
    }
    Remove-Item -LiteralPath $script:StateFile -Force -ErrorAction Stop
    Write-Log 'Restauracao finalizada.'
    return $true
}

function Find-Game($profiles) {
    foreach ($p in @($profiles)) {
        if (@(Read-ProcessesByName $p.processName).Count -gt 0) { return $p }
    }
    return $null
}

function Run-Monitor {
    $cfg = Read-Config
    $profiles = @(Read-Profiles)
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value.Replace('-','_')
    $mutex = New-Object Threading.Mutex($false,('Local\GameMode_' + $sid))
    $locked = $false
    try {
        $locked = $mutex.WaitOne(0)
        if (!$locked) { Write-Log 'Monitor ja esta em execucao.'; return }
        Remove-Item -LiteralPath $script:StopFile -Force -ErrorAction SilentlyContinue
        if (!(Restore-Session)) { throw 'Falha recuperando snapshot anterior.' }
        Write-Log ("Monitor iniciado. Versao 0.1.0, {0} perfis." -f $profiles.Count)
        $active = $null
        $lastSeen = Get-Date
        while (!(Test-Path -LiteralPath $script:StopFile)) {
            try {
                if ($null -eq $active) {
                    $next = Find-Game $profiles
                    if ($null -ne $next) {
                        Start-Profile $next $cfg
                        $active = $next
                        $lastSeen = Get-Date
                    }
                } else {
                    if (@(Read-ProcessesByName $active.processName).Count -gt 0) {
                        $lastSeen = Get-Date
                        if ($cfg.setAboveNormalPriority) { Save-GamePriority $active }
                    } elseif (((Get-Date)-$lastSeen).TotalSeconds -ge [int]$cfg.exitGraceSeconds) {
                        if (Restore-Session) { $active = $null }
                    }
                }
            } catch { Write-Log "Erro no ciclo de monitoramento: $_" 'ERROR' }
            Start-Sleep -Seconds ([int]$cfg.pollIntervalSeconds)
        }
    } finally {
        if ($locked) {
            try { [void](Restore-Session) } catch { Write-Log "Restaure manualmente: $_" 'ERROR' }
            [void]$mutex.ReleaseMutex()
        }
        $mutex.Dispose()
        Write-Log 'Monitor encerrado.'
    }
}

switch ($Action) {
    'Monitor' { Run-Monitor }
    'Restore' { if (!(Restore-Session)) { exit 2 } }
    'Status' {
        $state = Read-State
        if ($null -eq $state) { Write-Host 'Perfil: nenhum ativo.' }
        else { Write-Host "Perfil: $($state.game), iniciado $($state.startedAt)" }
        if (Test-Path $script:LogFile) { Get-Content $script:LogFile -Tail 15 }
    }
    'Scan' {
        $p = Find-Game @(Read-Profiles)
        if ($null -eq $p) { Write-Host 'Nenhum jogo reconhecido em execucao.' }
        else { Scan-Processes $p }
    }
    'Validate' {
        [void](Read-Config)
        $profiles = @(Read-Profiles)
        Write-Host ("OK: {0} perfis. Nenhuma lista de encerramento." -f $profiles.Count)
    }
}
