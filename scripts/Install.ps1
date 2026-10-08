#requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$taskName = 'PersonalGameModeV7'
$sourceRoot = Split-Path -Parent $PSScriptRoot
$destination = Join-Path $env:ProgramFiles 'PersonalGameModeV7'

function Is-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (!(Is-Admin)) {
    try {
        $file = $MyInvocation.MyCommand.Path
        $p = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$file+'"')) -Verb RunAs -Wait -PassThru
        exit $p.ExitCode
    } catch { Write-Host "Elevacao cancelada ou indisponivel: $_"; exit 1 }
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $sourceRoot 'scripts\SelfTest.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Falha no autoteste; nenhum agendamento foi criado.' }

$oldTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($oldTask) {
    throw 'Ja existe uma instalacao V7. Execute DESINSTALAR.cmd antes de reinstalar.'
}

New-Item -ItemType Directory -Path $destination -Force | Out-Null
foreach ($dir in @('src','profiles','scripts')) {
    New-Item -ItemType Directory -Path (Join-Path $destination $dir) -Force | Out-Null
    Copy-Item -Path (Join-Path $sourceRoot ($dir + '\*')) -Destination (Join-Path $destination $dir) -Recurse -Force -ErrorAction Stop
}
Copy-Item -LiteralPath (Join-Path $sourceRoot 'config.json') -Destination $destination -Force
$engine = Join-Path $destination 'src\GameMode.ps1'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $engine -Action Validate
if ($LASTEXITCODE -ne 0) { throw 'Validacao falhou; agendamento nao foi instalado.' }

$user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -Action Monitor' -f $engine) -WorkingDirectory $destination
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Seconds 0) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -StartWhenAvailable
Register-ScheduledTask -TaskName $taskName -Description 'Ativa automaticamente perfis reversiveis de desempenho ao detectar jogos.' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -ErrorAction Stop | Out-Null
Start-ScheduledTask -TaskName $taskName -ErrorAction Stop
Write-Host 'INSTALADO: monitor automatico iniciado.' -ForegroundColor Green
Write-Host "Diretorio: $destination"
Write-Host "Verificacao: execute STATUS.cmd do pacote, ou rode src\GameMode.ps1 -Action Status no diretorio instalado."
Write-Host 'Nao sao coletados FPS ou dados pessoais automaticamente.'
