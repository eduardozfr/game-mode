#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('Install','Start','Stop','Status','Uninstall','Validate')]
    [string]$Action
)
$ErrorActionPreference = 'Stop'
$script:SourceRoot = Split-Path -Parent $PSScriptRoot
$script:InstallRoot = Join-Path $env:LOCALAPPDATA 'GameMode'
$script:Task = 'GameMode.User'
$script:Engine = Join-Path $script:InstallRoot 'src\GameMode.ps1'
$script:StopFile = Join-Path $script:InstallRoot 'data\stop.signal'
$script:StateFile = Join-Path $script:InstallRoot 'data\state.json'

function Existing-Task {
    return Get-ScheduledTask -TaskName $script:Task -ErrorAction SilentlyContinue
}
function Restore-And-Stop {
    if (!(Test-Path -LiteralPath $script:Engine)) {
        Write-Host 'Instalacao local nao encontrada.'
        return
    }
    [void](New-Item -ItemType Directory -Path (Split-Path $script:StopFile) -Force)
    Set-Content -LiteralPath $script:StopFile -Value 'stop' -Encoding ASCII
    $task = Existing-Task
    if ($null -ne $task) {
        for ($i=0;$i -lt 12;$i++) {
            if ((Existing-Task).State -ne 'Running') { break }
            Start-Sleep -Seconds 1
        }
        if ((Existing-Task).State -eq 'Running') {
            Stop-ScheduledTask -TaskName $script:Task -ErrorAction Stop
        }
    }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:Engine -Action Restore
    if ($LASTEXITCODE -ne 0) { throw 'A restauracao nao terminou; a instalacao permanece intacta.' }
    Write-Host 'Monitor parado e configuracoes temporarias restauradas.'
}

switch ($Action) {
    'Validate' {
        $check = Join-Path $script:SourceRoot 'scripts\SelfTest.ps1'
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $check
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }
    'Install' {
        $check = Join-Path $script:SourceRoot 'scripts\SelfTest.ps1'
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $check
        if ($LASTEXITCODE -ne 0) { throw 'Validacao local falhou. Nao foi instalado.' }

        if ((Test-Path -LiteralPath $script:StateFile) -or $null -ne (Existing-Task)) {
            Restore-And-Stop
        }
        foreach ($dir in @('src','scripts','profiles','data')) {
            [void](New-Item -ItemType Directory -Path (Join-Path $script:InstallRoot $dir) -Force)
        }
        foreach ($f in @('src\GameMode.ps1','scripts\Manage.ps1','scripts\SelfTest.ps1','config.json','VERSION')) {
            $from = Join-Path $script:SourceRoot $f
            $to = Join-Path $script:InstallRoot $f
            if ($from -ne $to) { Copy-Item -LiteralPath $from -Destination $to -Force }
        }
        foreach ($p in @(Get-ChildItem (Join-Path $script:SourceRoot 'profiles') -Filter '*.json' -File)) {
            $to = Join-Path (Join-Path $script:InstallRoot 'profiles') $p.Name
            if ($p.FullName -ne $to) { Copy-Item -LiteralPath $p.FullName -Destination $to -Force }
        }

        $identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $arguments = '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -Action Monitor' -f $script:Engine
        $taskAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arguments
        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $identity
        $principal = New-ScheduledTaskPrincipal -UserId $identity -LogonType Interactive -RunLevel Limited
        $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Seconds 0) -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        Register-ScheduledTask -TaskName $script:Task -Action $taskAction -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
        Start-ScheduledTask -TaskName $script:Task
        Write-Host "Game Mode instalado em $script:InstallRoot"
        Write-Host 'Monitor iniciado e configurado para iniciar no proximo logon.'
    }
    'Start' {
        if ($null -eq (Existing-Task)) { throw 'Execute INSTALAR.cmd primeiro.' }
        Remove-Item -LiteralPath $script:StopFile -Force -ErrorAction SilentlyContinue
        Start-ScheduledTask -TaskName $script:Task
        Write-Host 'Monitor automatico iniciado.'
    }
    'Stop' { Restore-And-Stop }
    'Status' {
        $task = Existing-Task
        if ($null -eq $task) { Write-Host 'Agendamento: nao instalado.' }
        else { Write-Host "Agendamento: $($task.State)" }
        if (Test-Path $script:Engine) {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:Engine -Action Status
        }
        else { Write-Host 'Arquivos de instalacao nao encontrados.' }
    }
    'Uninstall' {
        if ((Test-Path $script:Engine) -or $null -ne (Existing-Task)) { Restore-And-Stop }
        if ($null -ne (Existing-Task)) {
            Unregister-ScheduledTask -TaskName $script:Task -Confirm:$false
        }
        if (Test-Path $script:InstallRoot) {
            Remove-Item -LiteralPath $script:InstallRoot -Recurse -Force
        }
        Write-Host 'Game Mode desinstalado. Nenhum programa foi fechado.'
    }
}
