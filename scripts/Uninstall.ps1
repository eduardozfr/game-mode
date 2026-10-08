#requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$taskName = 'PersonalGameModeV7'
$installRoot = Join-Path $env:ProgramFiles 'PersonalGameModeV7'
$engine = Join-Path $installRoot 'src\GameMode.ps1'

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

if (Test-Path -LiteralPath $engine) {
    $flag = Join-Path $installRoot 'data\stop.signal'
    New-Item -ItemType Directory -Path (Split-Path -Parent $flag) -Force | Out-Null
    Set-Content -LiteralPath $flag -Value 'stop' -Encoding ASCII
    for ($i=0; $i -lt 15; $i++) {
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if (!$task -or $task.State -ne 'Running') { break }
        Start-Sleep -Seconds 1
    }
}
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($task) {
    Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
}
if (Test-Path -LiteralPath $engine) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $engine -Action Restore
    if ($LASTEXITCODE -ne 0) { throw 'Estado nao totalmente restaurado. Arquivos foram preservados.' }
}
Write-Host 'Automacao desinstalada e configuracoes temporarias restauradas.' -ForegroundColor Green
Write-Host "Arquivos e logs preservados em $installRoot para revisao. Podem ser excluidos manualmente."
