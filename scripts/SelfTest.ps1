#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$failures = @()
foreach ($file in @(Get-ChildItem -LiteralPath $root -Filter '*.ps1' -Recurse -File)) {
    $tokens = $null
    $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$parseErrors)
    foreach ($err in @($parseErrors)) {
        $failures += ('{0}:{1}: {2}' -f $file.Name,$err.Extent.StartLineNumber,$err.Message)
    }
}
try {
    $cfg = Get-Content (Join-Path $root 'config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($cfg.schemaVersion -ne 1 -or $cfg.autoCloseProcesses -ne $false -or $cfg.stopServices -ne $false) {
        throw 'Configuracao nao respeita o modo seguro.'
    }
} catch { $failures += "config.json: $_" }
$ids = @()
foreach ($file in @(Get-ChildItem (Join-Path $root 'profiles') -Filter '*.json' -File)) {
    try {
        $p = Get-Content $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($p.id -notmatch '^[a-z][a-z0-9-]{1,39}$' -or $p.processName -notmatch '^[a-zA-Z0-9_-]{2,64}$') {
            throw 'ID ou executavel invalido.'
        }
        $ids += [string]$p.id
        foreach ($field in @('closeApps','stopServices','stopWSL','killApps','commands')) {
            if ($p.PSObject.Properties.Name -contains $field) { throw "Campo inseguro: $field" }
        }
    } catch { $failures += "$($file.Name): $_" }
}
if (@($ids | Select-Object -Unique).Count -ne $ids.Count) {
    $failures += 'Perfis com ID duplicado.'
}
if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "ERRO: $_" }
    exit 1
}
Write-Host ('OK: scripts PowerShell analisados, configuracao valida, {0} perfis verificados.' -f $ids.Count)
exit 0
