$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot '../setup-vitest-prettier.ps1'
$parseErrors = $null
$tokens = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $scriptPath, [ref] $tokens, [ref] $parseErrors
)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }

# Load only the script conversion function: never install dependencies or stop servers.
$function = $ast.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Enable-NodeInspector'
}, $true)
. ([scriptblock]::Create($function.Extent.Text))

$interviewParameter = $ast.ParamBlock.Parameters | Where-Object {
    $_.Name.VariablePath.UserPath -eq 'InterviewMode'
}
if ($interviewParameter.DefaultValue.Extent.Text -ne '$true') {
    throw 'Interview mode must default to true.'
}

$cases = @(
    @('tsx watch src/index.ts', 'tsx watch --inspect=9229 src/index.ts'),
    @('tsx.cmd watch --clear-screen=false src/index.ts', 'tsx.cmd watch --inspect=9229 --clear-screen=false src/index.ts'),
    @('tsx src/index.ts', 'tsx --inspect=9229 src/index.ts'),
    @('node --watch src/index.js', 'node --inspect=9229 --watch src/index.js'),
    @('node --inspect=9229 --import tsx watch src/index.ts', 'node --inspect=9229 --import tsx --watch src/index.ts'),
    @('node --import=tsx watch src/index.ts', 'node --inspect=9229 --import=tsx --watch src/index.ts'),
    @('node --watch --inspect=9229 --import tsx src/index.ts', 'node --watch --inspect=9229 --import tsx src/index.ts'),
    @('nodemon --exec tsx src/index.ts', 'nodemon --exec "node --inspect=9229 --import tsx" src/index.ts')
)
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('vitest-setup-test-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $testRoot | Out-Null
$packagePath = Join-Path $testRoot 'package.json'
try {
    foreach ($case in $cases) {
        @{ scripts = @{ dev = $case[0]; test = 'vitest' }; name = 'fixture' } |
            ConvertTo-Json | Set-Content -LiteralPath $packagePath
        if (-not (Enable-NodeInspector -ProjectDirectory $testRoot)) {
            throw "Failed to enable debugging for $($case[0])"
        }
        $result = Get-Content -LiteralPath $packagePath -Raw | ConvertFrom-Json
        if ($result.scripts.dev -ne $case[1] -or $result.scripts.test -ne 'vitest') {
            throw "Unexpected conversion for $($case[0]): $($result.scripts.dev)"
        }
        $before = Get-Content -LiteralPath $packagePath -Raw
        $null = Enable-NodeInspector -ProjectDirectory $testRoot
        if ((Get-Content -LiteralPath $packagePath -Raw) -ne $before) {
            throw "Conversion was not idempotent for $($case[0])"
        }
    }
    @{ scripts = @{ dev = 'vite --host 127.0.0.1' } } |
        ConvertTo-Json | Set-Content -LiteralPath $packagePath
    $before = Get-Content -LiteralPath $packagePath -Raw
    if (Enable-NodeInspector -ProjectDirectory $testRoot) { throw 'Unsupported command was accepted.' }
    if ((Get-Content -LiteralPath $packagePath -Raw) -ne $before) { throw 'Unsupported command was changed.' }
    Write-Host 'PASS: default interview mode, 9 command cases, and repeat-run safety.'
} finally {
    Remove-Item -LiteralPath $packagePath -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $testRoot
}
