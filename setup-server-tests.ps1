[CmdletBinding()]
param([string] $ProjectDirectory = '.', [switch] $SkipInstall)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'tools/common.ps1')
Invoke-SetupAction 'server-tests' @{ project = $ProjectDirectory; skipInstall = [bool]$SkipInstall }
