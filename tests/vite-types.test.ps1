$ErrorActionPreference = 'Stop'
& node --test --test-name-pattern='Vite source/root' (Join-Path $PSScriptRoot 'setup.test.cjs')
if ($LASTEXITCODE -ne 0) { throw 'Vite type tests failed.' }
