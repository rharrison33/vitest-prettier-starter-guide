[CmdletBinding()]
param([string] $ProjectDirectory = '.')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'tools/common.ps1')
Invoke-SetupAction 'vite-types' @{ project = $ProjectDirectory }
