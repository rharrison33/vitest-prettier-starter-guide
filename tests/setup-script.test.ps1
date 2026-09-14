$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
foreach ($file in @(Get-ChildItem $repoRoot -Filter '*.ps1') + @(Get-ChildItem (Join-Path $repoRoot 'tools') -Filter '*.ps1')) {
    $tokens = $null
    $parseErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
}
& node --test (Join-Path $PSScriptRoot 'setup.test.cjs')
if ($LASTEXITCODE -ne 0) { throw 'Setup tests failed.' }
& (Join-Path $PSScriptRoot 'process-cleanup.test.ps1')
Write-Host 'PASS: PowerShell scripts parse and fixture checks pass. No packages were installed or real processes stopped.'
