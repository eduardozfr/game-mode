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
$engine = Join-Path $installRoot 'src\GameMode.ps1'
if (!(Test-Path -LiteralPath $engine)) { throw 'V7 nao instalada.' }
Remove-Item -LiteralPath (Join-Path $installRoot 'data\stop.signal') -Force -ErrorAction SilentlyContinue
Start-ScheduledTask -TaskName 'PersonalGameModeV7' -ErrorAction Stop
Write-Host 'Monitor automatico iniciado.'
