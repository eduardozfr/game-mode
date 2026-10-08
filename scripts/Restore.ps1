#requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
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
$installRoot = Join-Path $env:ProgramFiles 'PersonalGameModeV7'
$taskName = 'PersonalGameModeV7'
$engine = Join-Path $installRoot 'src\GameMode.ps1'
if (!(Test-Path -LiteralPath $engine)) { throw 'V7 nao instalada.' }
$flag = Join-Path $installRoot 'data\stop.signal'
New-Item -ItemType Directory -Path (Split-Path -Parent $flag) -Force | Out-Null
Set-Content -LiteralPath $flag -Value 'stop' -Encoding ASCII
$stopped = $false
for ($i=0; $i -lt 20; $i++) {
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if (!$task -or $task.State -ne 'Running') { $stopped = $true; break }
    Start-Sleep -Seconds 1
}
if (!$stopped) {
    Write-Host 'Monitor demorou para encerrar; interrompendo tarefa.'
    Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $engine -Action Restore
if ($LASTEXITCODE -ne 0) { throw 'Restauracao incompleta. Confira os logs antes de reiniciar o monitor.' }
Write-Host 'Configuracoes restauradas. Para reativar a automacao, use REATIVAR.cmd.'
