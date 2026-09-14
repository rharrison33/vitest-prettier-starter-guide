[CmdletBinding()]
param([string] $ProjectDirectory = '.', [switch] $SkipInstall, [switch] $SkipVSCodeExtension)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'tools/common.ps1')
Invoke-SetupAction 'formatting' @{ project = $ProjectDirectory; skipInstall = [bool]$SkipInstall }
if (-not $SkipInstall -and -not $SkipVSCodeExtension) {
    if (Get-Command code -ErrorAction SilentlyContinue) {
        $extensions = & code --list-extensions
        if ('esbenp.prettier-vscode' -notin $extensions) {
            & code --install-extension esbenp.prettier-vscode
            if ($LASTEXITCODE -ne 0) { Write-Warning 'Install the Prettier VS Code extension manually to enable format on save.' }
        }
    } else { Write-Warning 'VS Code CLI not found. Install the Prettier extension manually to enable format on save.' }
}
