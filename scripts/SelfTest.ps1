#requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$failures = @()
foreach ($file in @(Get-ChildItem -LiteralPath $root -Recurse -Filter '*.ps1' -File)) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
    foreach ($errorItem in @($parseErrors)) {
        $failures += ("{0}:{1} {2}" -f $file.Name, $errorItem.Extent.StartLineNumber, $errorItem.Message)
    }
}
foreach ($jsonFile in @(Get-ChildItem -LiteralPath $root -Recurse -Filter '*.json' -File)) {
    try { [void](Get-Content -LiteralPath $jsonFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json) }
    catch { $failures += ("JSON invalido {0}: {1}" -f $jsonFile.Name, $_) }
}
if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host $failure -ForegroundColor Red }
    exit 1
}
Write-Host 'OK: scripts PowerShell e arquivos JSON sem erros de sintaxe.' -ForegroundColor Green
