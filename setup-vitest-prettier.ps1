[CmdletBinding()]
param(
    [switch] $InterviewMode = $true,

    [switch] $Force,

    [switch] $SkipVSCodeExtension,

    [switch] $SkipDevProcessCleanup,

    [switch] $SkipDebugScriptUpdate
)

$ErrorActionPreference = 'Stop'

function Stop-DevelopmentProcesses {
    param(
        [int[]] $Ports = @(3000, 3001, 4000, 5000, 5173, 5174, 5175, 8080)
    )

    $processIds = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
        Where-Object { $_.LocalPort -in $Ports } |
        Select-Object -ExpandProperty OwningProcess -Unique

    if (-not $processIds) {
        Write-Host 'No development servers are currently using the common local ports.' -ForegroundColor DarkGray
        return
    }

    foreach ($processId in $processIds) {
        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
        if (-not $process) {
            continue
        }

        Write-Host "Stopping $($process.ProcessName) (PID $processId)..." -ForegroundColor Yellow
        Stop-Process -Id $processId -Force
    }
}

function Write-SetupFile {
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Content
    )

    $fullPath = Join-Path (Get-Location) $Path
    $normalizedContent = $Content.Trim() + [Environment]::NewLine

    if (Test-Path -LiteralPath $fullPath) {
        $currentContent = Get-Content -LiteralPath $fullPath -Raw
        if ($currentContent.Trim() -eq $Content.Trim()) {
            Write-Host "Unchanged: $Path" -ForegroundColor DarkGray
            return
        }

        if (-not $Force) {
            Write-Warning "Skipped existing $Path. Rerun with -Force to back it up and replace it."
            return
        }

        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backupPath = "$fullPath.$timestamp.backup"
        Copy-Item -LiteralPath $fullPath -Destination $backupPath
        Write-Host "Backed up $Path to $backupPath" -ForegroundColor Yellow
    }

    $parentDirectory = Split-Path -Parent $fullPath
    if ($parentDirectory) {
        New-Item -ItemType Directory -Path $parentDirectory -Force | Out-Null
    }

    Set-Content -LiteralPath $fullPath -Value $normalizedContent -Encoding utf8 -NoNewline
    Write-Host "Created: $Path" -ForegroundColor Green
}

if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    throw 'npm was not found. Install Node.js, reopen PowerShell, and run this script again.'
}

if (-not (Test-Path -LiteralPath 'package.json')) {
    throw 'No package.json was found. Run this script from the root of an npm project.'
}

function Test-ReactProject {
    $packagePaths = @('package.json', 'client/package.json', 'frontend/package.json', 'web/package.json')

    foreach ($packagePath in $packagePaths) {
        if (-not (Test-Path -LiteralPath $packagePath)) {
            continue
        }

        try {
            $packageJson = Get-Content -LiteralPath $packagePath -Raw | ConvertFrom-Json
            $dependencyNames = @($packageJson.dependencies.PSObject.Properties.Name)
            $devDependencyNames = @($packageJson.devDependencies.PSObject.Properties.Name)
            if ('react' -in $dependencyNames -or 'react' -in $devDependencyNames) {
                return $true
            }
        } catch {
            Write-Warning "Could not inspect $packagePath for React dependencies."
        }
    }

    return $false
}

if ($InterviewMode) {
    $SkipVSCodeExtension = $true
    Write-Host 'Interview mode: using detected defaults and skipping extension installation.' -ForegroundColor Cyan
}

if (-not $SkipDevProcessCleanup) {
    Write-Host 'Stopping stale local development servers...' -ForegroundColor Cyan
    Stop-DevelopmentProcesses
}

if ($InterviewMode) {
    $includeReactTesting = Test-ReactProject
    $reactTestingMessage = if ($includeReactTesting) { 'enabled' } else { 'not needed' }
    Write-Host "React Testing Library and jsdom: $reactTestingMessage" -ForegroundColor DarkGray
} else {
    do {
        $reactAnswer = Read-Host 'Install React Testing Library and jsdom? (y/n)'
    } until ($reactAnswer -match '^(?i:y(?:es)?|n(?:o)?)$')

    $includeReactTesting = $reactAnswer -match '^(?i:y(?:es)?)$'
}

$testEnvironment = if ($includeReactTesting) { 'jsdom' } else { 'node' }

Write-Host 'Installing Vitest, Prettier, Supertest, and coverage support...' -ForegroundColor Cyan
npm install --save-dev vitest prettier supertest '@types/supertest' '@vitest/coverage-v8'
if ($LASTEXITCODE -ne 0) {
    throw "npm install failed with exit code $LASTEXITCODE."
}

if ($includeReactTesting) {
    Write-Host 'Installing React testing dependencies...' -ForegroundColor Cyan
    npm install --save-dev jsdom '@testing-library/react' '@testing-library/jest-dom'
    if ($LASTEXITCODE -ne 0) {
        throw "React testing dependency installation failed with exit code $LASTEXITCODE."
    }
}

Write-Host 'Adding npm scripts...' -ForegroundColor Cyan
$packageScripts = @(
    'scripts.test=vitest'
    'scripts.test:run=vitest --run'
    'scripts.test:coverage=vitest --coverage'
    'scripts.format=prettier --write .'
    'scripts.format:check=prettier --check .'
)

foreach ($packageScript in $packageScripts) {
    npm pkg set $packageScript
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to add npm script: $packageScript"
    }
}

$vitestConfig = @"
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "$testEnvironment",
    globals: true,
  },
});
"@

$prettierConfig = @'
{
  "semi": true,
  "singleQuote": false,
  "tabWidth": 2,
  "trailingComma": "es5"
}
'@

$prettierIgnore = @'
node_modules
dist
build
coverage
package-lock.json
'@

$vscodeSettings = @'
{
  "editor.defaultFormatter": "esbenp.prettier-vscode",
  "editor.formatOnSave": true,
  "[javascript]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode"
  },
  "[javascriptreact]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode"
  },
  "[typescript]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode"
  },
  "[typescriptreact]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode"
  },
  "[json]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode"
  }
}
'@

function Find-NodeServerEntryPoint {
    $projectDirectories = @('server', 'backend', 'api', '.')
    $entryPointCandidates = @(
        'src/server.ts',
        'src/index.ts',
        'server.ts',
        'index.ts',
        'src/server.js',
        'src/index.js',
        'server.js',
        'index.js'
    )

    foreach ($projectDirectory in $projectDirectories) {
        if ($projectDirectory -ne '.' -and -not (Test-Path -LiteralPath "$projectDirectory/package.json")) {
            continue
        }

        foreach ($entryPoint in $entryPointCandidates) {
            $candidatePath = if ($projectDirectory -eq '.') {
                $entryPoint
            } else {
                Join-Path $projectDirectory $entryPoint
            }

            if (Test-Path -LiteralPath $candidatePath) {
                return [pscustomobject]@{
                    ProjectDirectory = $projectDirectory
                    EntryPoint       = $entryPoint.Replace('\', '/')
                }
            }
        }
    }

    return $null
}

$debugTarget = Find-NodeServerEntryPoint

if ($debugTarget) {
    $debugProjectDirectory = $debugTarget.ProjectDirectory
    $debugWorkingDirectory = if ($debugTarget.ProjectDirectory -eq '.') {
        '${workspaceFolder}'
    } else {
        '${workspaceFolder}/' + $debugTarget.ProjectDirectory
    }
    $debugEntryPoint = $debugTarget.EntryPoint
    Write-Host "Debug target detected: $debugWorkingDirectory/$debugEntryPoint" -ForegroundColor DarkGray
} else {
    $debugProjectDirectory = '.'
    $debugWorkingDirectory = '${workspaceFolder}'
    $debugEntryPoint = 'src/server.ts'
    Write-Warning 'No common Node server entry point was found. Using src/server.ts in launch.json; edit it if needed.'
}

$debugUsesTypeScript = $debugEntryPoint.EndsWith('.ts') -or $debugEntryPoint.EndsWith('.tsx')
$debugRuntimeExecutable = if ($debugUsesTypeScript) { 'npx' } else { 'node' }
$debugRuntimeArguments = if ($debugUsesTypeScript) {
    '["tsx", "' + $debugEntryPoint + '"]'
} else {
    '["' + $debugEntryPoint + '"]'
}

function Enable-NodeInspector {
    param(
        [string] $ProjectDirectory,
        [int] $InspectorPort = 9229
    )

    $packagePath = if ($ProjectDirectory -eq '.') {
        'package.json'
    } else {
        Join-Path $ProjectDirectory 'package.json'
    }

    if (-not (Test-Path -LiteralPath $packagePath)) {
        return $false
    }

    $packageJson = Get-Content -LiteralPath $packagePath -Raw | ConvertFrom-Json
    $devScript = [string] $packageJson.scripts.dev
    if (-not $devScript) {
        Write-Warning "$packagePath does not contain a dev script. The generated debugger will launch the server instead."
        return $false
    }

    # Repair commands produced by older versions before checking for an inspector.
    # With node, watch is a flag; with tsx, it is a CLI subcommand.
    $repairedDevScript = $devScript -replace '(^\s*node\s+.*?--import(?:=|\s+)tsx\s+)watch(?=\s|$)', '${1}--watch'
    if ($repairedDevScript -ne $devScript) {
        $devScript = $repairedDevScript
        $packageJson.scripts.dev = $devScript
        $packageJson | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $packagePath -Encoding utf8
        Write-Host "Repaired Node watch flag in $packagePath." -ForegroundColor Green
    }

    if ($devScript -match '--inspect(?:-brk)?(?:=|\s|$)') {
        Write-Host "Node inspector already enabled in $packagePath." -ForegroundColor DarkGray
        return $true
    }

    $updatedDevScript = $null
    if ($devScript -match '--exec\s+tsx(?:\.cmd)?\b') {
        $updatedDevScript = $devScript -replace '--exec\s+tsx(?:\.cmd)?\b', "--exec `"node --inspect=$InspectorPort --import tsx`""
    } elseif ($devScript -match '^\s*tsx(?:\.cmd)?\s+watch(?:\s|$)') {
        $updatedDevScript = $devScript -replace '^(\s*tsx(?:\.cmd)?\s+watch)(?=\s|$)', "`${1} --inspect=$InspectorPort"
    } elseif ($devScript -match '^\s*tsx(?:\.cmd)?\s+') {
        $updatedDevScript = $devScript -replace '^(\s*tsx(?:\.cmd)?)(?=\s)', "`${1} --inspect=$InspectorPort"
    } elseif ($devScript -match '^\s*node\s+') {
        $updatedDevScript = $devScript -replace '^\s*node\s+', "node --inspect=$InspectorPort "
    }

    if (-not $updatedDevScript) {
        Write-Warning "Could not safely add the Node inspector to '$devScript'. The generated debugger will launch the server instead."
        return $false
    }

    $packageJson.scripts.dev = $updatedDevScript
    $packageJson | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $packagePath -Encoding utf8
    Write-Host "Enabled the Node inspector on port $InspectorPort in $packagePath." -ForegroundColor Green
    return $true
}

$nodeInspectorPort = 9229
$nodeInspectorEnabled = if ($SkipDebugScriptUpdate) {
    $false
} else {
    Enable-NodeInspector -ProjectDirectory $debugProjectDirectory -InspectorPort $nodeInspectorPort
}

if ($nodeInspectorEnabled) {
    $nodeDebugConfiguration = @'
    {
      "name": "Debug Node Server",
      "type": "node",
      "request": "attach",
      "port": __NODE_INSPECTOR_PORT__,
      "restart": true,
      "localRoot": "__DEBUG_WORKING_DIRECTORY__",
      "skipFiles": ["<node_internals>/**"]
    }
'@.Replace('__NODE_INSPECTOR_PORT__', $nodeInspectorPort).
        Replace('__DEBUG_WORKING_DIRECTORY__', $debugWorkingDirectory)
} else {
    $nodeDebugConfiguration = @'
    {
      "name": "Debug Node Server",
      "type": "node",
      "request": "launch",
      "runtimeExecutable": "__DEBUG_RUNTIME_EXECUTABLE__",
      "runtimeArgs": __DEBUG_RUNTIME_ARGUMENTS__,
      "cwd": "__DEBUG_WORKING_DIRECTORY__",
      "skipFiles": ["<node_internals>/**"],
      "console": "integratedTerminal"
    }
'@.Replace('__DEBUG_RUNTIME_EXECUTABLE__', $debugRuntimeExecutable).
        Replace('__DEBUG_RUNTIME_ARGUMENTS__', $debugRuntimeArguments).
        Replace('__DEBUG_WORKING_DIRECTORY__', $debugWorkingDirectory)
}

function Find-ReactClient {
    $clientDirectories = @('client', 'frontend', 'web', '.')

    foreach ($clientDirectory in $clientDirectories) {
        $packagePath = if ($clientDirectory -eq '.') { 'package.json' } else { Join-Path $clientDirectory 'package.json' }
        if (-not (Test-Path -LiteralPath $packagePath)) { continue }

        try {
            $packageJson = Get-Content -LiteralPath $packagePath -Raw | ConvertFrom-Json
            $dependencyNames = @($packageJson.dependencies.PSObject.Properties.Name)
            $devDependencyNames = @($packageJson.devDependencies.PSObject.Properties.Name)
            if ('react' -in $dependencyNames -or 'react' -in $devDependencyNames) {
                return $clientDirectory
            }
        } catch {
            Write-Warning "Could not inspect $packagePath for React dependencies."
        }
    }

    return $null
}

function Initialize-ViteClientTypes {
    param([Parameter(Mandatory)][string] $ProjectDirectory)

    $packagePath = Join-Path $ProjectDirectory 'package.json'
    if (-not (Test-Path -LiteralPath $packagePath)) { return }
    try {
        $packageJson = Get-Content -LiteralPath $packagePath -Raw | ConvertFrom-Json
    } catch {
        Write-Warning "Could not inspect $packagePath for Vite dependencies."
        return
    }
    $dependencies = @($packageJson.dependencies.PSObject.Properties.Name) +
        @($packageJson.devDependencies.PSObject.Properties.Name)
    if ('vite' -notin $dependencies) { return }

    $sourceDirectory = Join-Path $ProjectDirectory 'src'
    $rootDeclaration = Join-Path $ProjectDirectory 'vite-env.d.ts'
    $sourceDeclaration = Join-Path $sourceDirectory 'vite-env.d.ts'
    # Preserve existing declarations, including custom content, even with -Force.
    if ((Test-Path -LiteralPath $rootDeclaration) -or (Test-Path -LiteralPath $sourceDeclaration)) { return }
    $declaration = if (Test-Path -LiteralPath $sourceDirectory -PathType Container) {
        $sourceDeclaration
    } else {
        $rootDeclaration
    }
    Set-Content -LiteralPath $declaration -Value '/// <reference types="vite/client" />' -Encoding utf8
    Write-Host "Created Vite client types: $declaration" -ForegroundColor Green
}

foreach ($directory in @('client', 'frontend', 'web', '.')) {
    Initialize-ViteClientTypes -ProjectDirectory $directory
}

$reactClientDirectory = Find-ReactClient
$reactDebugConfiguration = ''
$debugCompound = ''

if ($reactClientDirectory) {
    $reactWebRoot = if ($reactClientDirectory -eq '.') {
        '${workspaceFolder}/src'
    } else {
        '${workspaceFolder}/' + $reactClientDirectory + '/src'
    }

    $viteConfigDirectory = if ($reactClientDirectory -eq '.') { '.' } else { $reactClientDirectory }
    $viteConfig = Get-Item -LiteralPath "$viteConfigDirectory/vite.config.ts", "$viteConfigDirectory/vite.config.js" -ErrorAction SilentlyContinue |
        Select-Object -First 1
    $reactPort = 5173

    if ($viteConfig) {
        $viteConfigContent = Get-Content -LiteralPath $viteConfig.FullName -Raw
        $portMatch = [regex]::Match($viteConfigContent, '\bport\s*:\s*(?<port>\d+)')
        if ($portMatch.Success) {
            $reactPort = [int] $portMatch.Groups['port'].Value
        }
    }

    $reactDebugConfiguration = @'
,
    {
      "name": "Debug React Client",
      "type": "chrome",
      "request": "launch",
      "url": "http://localhost:__REACT_PORT__",
      "webRoot": "__REACT_WEB_ROOT__"
    }
'@.Replace('__REACT_PORT__', $reactPort).
        Replace('__REACT_WEB_ROOT__', $reactWebRoot)

    $debugCompound = @'
,
  "compounds": [
    {
      "name": "Debug Full Stack",
      "configurations": ["Debug Node Server", "Debug React Client"]
    }
  ]
'@

    Write-Host "React debug target detected: http://localhost:$reactPort ($reactWebRoot)" -ForegroundColor DarkGray
}

$vscodeLaunch = @'
{
  "version": "0.2.0",
  "configurations": [
__NODE_DEBUG_CONFIGURATION____REACT_DEBUG_CONFIGURATION__
  ]__DEBUG_COMPOUND__
}
'@.Replace('__NODE_DEBUG_CONFIGURATION__', $nodeDebugConfiguration).
    Replace('__REACT_DEBUG_CONFIGURATION__', $reactDebugConfiguration).
    Replace('__DEBUG_COMPOUND__', $debugCompound)

function Find-LiteralGetRoutes {
    param(
        [string] $ProjectDirectory = '.'
    )

    $searchRoot = if ($ProjectDirectory -eq '.') { '.' } else { $ProjectDirectory }
    $sourceFiles = Get-ChildItem -LiteralPath $searchRoot -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Extension -in @('.ts', '.tsx', '.js', '.mjs', '.cjs') -and
            $_.FullName -notmatch '[\\/](node_modules|dist|build|coverage)[\\/]'
        }

    $routePattern = '(?m)\.(?:get)\s*\(\s*["''](?<route>/[^"'']+)["'']'
    $routes = foreach ($sourceFile in $sourceFiles) {
        $source = Get-Content -LiteralPath $sourceFile.FullName -Raw
        foreach ($match in [regex]::Matches($source, $routePattern)) {
            [pscustomobject]@{
                Route = $match.Groups['route'].Value
                File  = $sourceFile.FullName
            }
        }
    }

    return $routes | Sort-Object Route, File -Unique
}

$detectedRoutes = @(Find-LiteralGetRoutes -ProjectDirectory $debugProjectDirectory)
$healthRoute = $detectedRoutes |
    Where-Object { $_.Route -match '(^|/)health(?:/|$)' } |
    Select-Object -First 1
$collectionRoute = $detectedRoutes |
    Where-Object { $_.Route -notmatch ':' -and $_.Route -notmatch '(^|/)health(?:/|$)' } |
    Sort-Object @{ Expression = { if ($_.Route -like '/api/*') { 0 } else { 1 } } }, Route |
    Select-Object -First 1

$healthEndpointPath = if ($healthRoute) { $healthRoute.Route } else { '/api/health' }
$itemsEndpointPath = if ($collectionRoute) { $collectionRoute.Route } else { '/api/items' }
$itemsPropertyName = ($itemsEndpointPath.Trim('/') -split '/')[-1] -replace '[^A-Za-z0-9_$]', ''
if (-not $itemsPropertyName) {
    $itemsPropertyName = 'items'
}

$appSourceFile = Get-ChildItem -LiteralPath $debugProjectDirectory -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Extension -in @('.ts', '.tsx', '.js', '.mjs', '.cjs') -and
        $_.FullName -notmatch '[\\/](node_modules|dist|build|coverage)[\\/]'
    } |
    Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match 'export\s+(?:const|let|var)\s+app\b' } |
    Select-Object -First 1

if ($appSourceFile) {
    $projectRoot = (Get-Location).Path.TrimEnd('\') + '\'
    $relativeAppPath = $appSourceFile.FullName.Replace($projectRoot, '').Replace('\', '/')
    $appImportPath = './' + ($relativeAppPath -replace '\.(?:ts|tsx|js|mjs|cjs)$', '')
} else {
    $appImportPath = './server'
    Write-Warning 'Could not find an exported variable named app. Using ./server in the generated test; update the import if needed.'
}

Write-Host "Routes detected: health=$healthEndpointPath, collection=$itemsEndpointPath, property=$itemsPropertyName" -ForegroundColor DarkGray

$serverTest = @'
import { describe, expect, it } from "vitest";
import request from "supertest";
import { app } from "__APP_IMPORT_PATH__";

const HEALTH_ENDPOINT_PATH = "__HEALTH_ENDPOINT_PATH__";
const ITEMS_ENDPOINT_PATH = "__ITEMS_ENDPOINT_PATH__";
const ITEMS_PROPERTY_NAME = "__ITEMS_PROPERTY_NAME__";

describe(`GET ${HEALTH_ENDPOINT_PATH}`, () => {
  it("returns a successful health response", async () => {
    const response = await request(app).get(HEALTH_ENDPOINT_PATH);

    expect(response.status).toBe(200);
  });
});

describe(`GET ${ITEMS_ENDPOINT_PATH}`, () => {
  it("returns an items array", async () => {
    const response = await request(app)
      .get(ITEMS_ENDPOINT_PATH)
      .query({ page: 1, pageSize: 25 });

    expect(response.status).toBe(200);
    const items = Array.isArray(response.body)
      ? response.body
      : response.body[ITEMS_PROPERTY_NAME];

    expect(Array.isArray(items)).toBe(true);
  });
});
'@.Replace('__APP_IMPORT_PATH__', $appImportPath).
    Replace('__HEALTH_ENDPOINT_PATH__', $healthEndpointPath).
    Replace('__ITEMS_ENDPOINT_PATH__', $itemsEndpointPath).
    Replace('__ITEMS_PROPERTY_NAME__', $itemsPropertyName)

Write-SetupFile -Path 'vitest.config.ts' -Content $vitestConfig
Write-SetupFile -Path '.prettierrc.json' -Content $prettierConfig
Write-SetupFile -Path '.prettierignore' -Content $prettierIgnore
Write-SetupFile -Path '.vscode/settings.json' -Content $vscodeSettings
Write-SetupFile -Path '.vscode/launch.json' -Content $vscodeLaunch
Write-SetupFile -Path 'server.test.ts' -Content $serverTest

if (-not $SkipVSCodeExtension) {
    if (Get-Command code -ErrorAction SilentlyContinue) {
        Write-Host 'Installing the VS Code Prettier extension...' -ForegroundColor Cyan
        code --install-extension esbenp.prettier-vscode
        if ($LASTEXITCODE -ne 0) {
            Write-Warning 'VS Code could not install the Prettier extension.'
        }
    } else {
        Write-Warning 'The code command was not found; skipping the VS Code extension.'
    }
}

Write-Host ''
Write-Host 'Setup complete.' -ForegroundColor Green
Write-Host 'Run npm run format to format the project.'
Write-Host 'Create a test file, then run npm run test:run to verify Vitest.'
if ($nodeInspectorEnabled -and $reactClientDirectory) {
    Write-Host 'For full-stack debugging: run npm run dev, select Debug Full Stack in VS Code, and press F5.'
} elseif ($nodeInspectorEnabled) {
    Write-Host 'For backend debugging: run npm run dev, select Debug Node Server in VS Code, and press F5.'
}
