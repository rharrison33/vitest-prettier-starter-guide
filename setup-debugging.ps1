[CmdletBinding()]
param([string] $ProjectDirectory = '.', [string] $ScriptName = 'dev', [string] $ClientUrl)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'tools/common.ps1')
Invoke-SetupAction 'debugging' @{ project = $ProjectDirectory; script = $ScriptName; clientUrl = $ClientUrl }
