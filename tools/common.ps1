function Invoke-SetupAction {
    param([string] $Action, [hashtable] $Options)
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'Node.js was not found. Install the version required by your project first.' }
    $Options.root = (Get-Location).Path
    $Options | ConvertTo-Json -Compress | & node (Join-Path $PSScriptRoot 'setup.cjs') $Action
    if ($LASTEXITCODE -ne 0) { throw "$Action setup failed; see the message above." }
}
