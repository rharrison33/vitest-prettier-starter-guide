$ErrorActionPreference = 'Stop'
# All process commands below are fake: no real listener is queried or stopped.
function Get-NetTCPConnection {
    param($State, $ErrorAction)
    @(
        [pscustomobject]@{ LocalPort = 3001; OwningProcess = 10001 },
        [pscustomobject]@{ LocalPort = 5173; OwningProcess = 10002 }
    )
}
function Get-Process {
    param($Id, $ErrorAction)
    [pscustomobject]@{ Id = $Id; ProcessName = $(if ($Id -eq 10001) { 'node' } else { 'other' }); StartTime = [datetime]'2026-01-01' }
}
function Stop-Process {
    param($Id, $ErrorAction)
    $recordedStops.Add([int]$Id)
}
$recordedStops = [System.Collections.Generic.List[int]]::new()
$cleanup = Join-Path (Split-Path $PSScriptRoot -Parent) 'stop-dev-processes.ps1'
& $cleanup
if ($recordedStops.Count) { throw 'Preview stopped a process.' }
& $cleanup -Stop -WhatIf
if ($recordedStops.Count) { throw 'WhatIf stopped a process.' }
& $cleanup -Stop
if ($recordedStops.Count -ne 1 -or $recordedStops[0] -ne 10001) { throw 'Default stop must only target the fake Node process.' }
$recordedStops = [System.Collections.Generic.List[int]]::new()
& $cleanup -Ports 5173 -Stop -IncludeOtherProcesses
if ($recordedStops.Count -ne 1 -or $recordedStops[0] -ne 10002) { throw 'Explicit port and process override failed.' }
Write-Host 'PASS: process cleanup preview, WhatIf, Node filtering, and port filtering (mocked).'
