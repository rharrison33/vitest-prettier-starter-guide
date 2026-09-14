$ErrorActionPreference = 'Stop'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot '../setup-vitest-prettier.ps1'), [ref] $tokens, [ref] $parseErrors
)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
$function = $ast.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Initialize-ViteClientTypes'
}, $true)
. ([scriptblock]::Create($function.Extent.Text))

$testDirectory = Join-Path ([IO.Path]::GetTempPath()) ('vite-types-test-' + [guid]::NewGuid())
$sourceDirectory = Join-Path $testDirectory 'src'
$packagePath = Join-Path $testDirectory 'package.json'
$sourceDeclaration = Join-Path $sourceDirectory 'vite-env.d.ts'
$rootDeclaration = Join-Path $testDirectory 'vite-env.d.ts'
New-Item -ItemType Directory -Path $sourceDirectory -Force | Out-Null
try {
    Initialize-ViteClientTypes -ProjectDirectory $testDirectory
    '{"dependencies":{"react":"*"}}' | Set-Content -LiteralPath $packagePath
    Initialize-ViteClientTypes -ProjectDirectory $testDirectory
    if (Test-Path $sourceDeclaration) { throw 'Non-Vite project was changed.' }
    foreach ($section in @('dependencies', 'devDependencies')) {
        @{ $section = @{ vite = '*' } } | ConvertTo-Json | Set-Content -LiteralPath $packagePath
        Initialize-ViteClientTypes -ProjectDirectory $testDirectory
        if ((Get-Content $sourceDeclaration -Raw).Trim() -ne '/// <reference types="vite/client" />') { throw 'Missing Vite declaration.' }
        '// custom declarations' | Set-Content -LiteralPath $sourceDeclaration
        $before = [IO.File]::ReadAllBytes($sourceDeclaration)
        $Force = $true
        Initialize-ViteClientTypes -ProjectDirectory $testDirectory
        if ([Convert]::ToBase64String($before) -ne [Convert]::ToBase64String([IO.File]::ReadAllBytes($sourceDeclaration))) { throw 'Existing declaration was overwritten.' }
        Remove-Item -LiteralPath $sourceDeclaration
    }
    '// existing root declaration' | Set-Content -LiteralPath $rootDeclaration
    Initialize-ViteClientTypes -ProjectDirectory $testDirectory
    if (Test-Path $sourceDeclaration) { throw 'Created duplicate declaration despite root file.' }
    Remove-Item -LiteralPath $rootDeclaration
    Remove-Item -LiteralPath $sourceDirectory
    Initialize-ViteClientTypes -ProjectDirectory $testDirectory
    if (-not (Test-Path $rootDeclaration)) { throw 'Root-level Vite project was missed.' }
    Write-Host 'PASS: Vite dependency detection, source/root layouts, existing-file preservation, and non-Vite skip.'
} finally {
    foreach ($file in @($sourceDeclaration, $rootDeclaration, $packagePath)) {
        Remove-Item -LiteralPath $file -ErrorAction SilentlyContinue
    }
    if (Test-Path $sourceDirectory) { Remove-Item -LiteralPath $sourceDirectory }
    Remove-Item -LiteralPath $testDirectory
}
