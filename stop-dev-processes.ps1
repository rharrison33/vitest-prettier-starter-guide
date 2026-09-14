[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateRange(1,65535)][int[]] $Ports = @(3001,5173,9229),
    [switch] $Stop,
    [switch] $IncludeOtherProcesses
)
$ErrorActionPreference = 'Stop'
$connections = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -in $Ports })
$processes = @($connections | Select-Object -ExpandProperty OwningProcess -Unique | ForEach-Object {
    $process = Get-Process -Id $_ -ErrorAction SilentlyContinue
    if ($process) {
        [pscustomobject]@{
            Id = $process.Id
            Name = $process.ProcessName
            Ports = ($connections | Where-Object OwningProcess -eq $process.Id | Select-Object -ExpandProperty LocalPort -Unique) -join ','
            Started = $process.StartTime
        }
    }
})
if (-not $processes.Count) { Write-Host 'No listeners found on the specified ports.'; return }
$processes | Format-Table Id,Name,Ports
if (-not $Stop) { Write-Host 'Preview only. Rerun with -Stop to stop Node processes on these ports. Narrow -Ports first if needed.'; return }
foreach ($process in $processes) {
    if ($process.Name -ne 'node' -and -not $IncludeOtherProcesses) {
        Write-Warning "Skipping non-Node process $($process.Name), PID $($process.Id)."; continue
    }
    $current = Get-Process -Id $process.Id -ErrorAction SilentlyContinue
    if (-not $current -or $current.StartTime -ne $process.Started) { continue }
    if ($PSCmdlet.ShouldProcess("$($process.Name), PID $($process.Id), ports $($process.Ports)", 'Stop process')) {
        Stop-Process -Id $process.Id -ErrorAction Stop
    }
}
