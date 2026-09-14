[CmdletBinding()]
param(
    [switch] $InterviewMode = $true,
    [switch] $Force,
    [switch] $SkipVSCodeExtension,
    [switch] $SkipDevProcessCleanup,
    [switch] $SkipDebugScriptUpdate
)
Write-Warning 'The all-in-one setup has been retired. Nothing was installed, changed, or stopped.'
Write-Host 'Choose setup-formatting, setup-server-tests, setup-client-tests, setup-debugging, setup-vite-types, or stop-dev-processes. See README.md for commands.'
