[CmdletBinding()]
param(
    [switch] $Force,

    [switch] $SkipVSCodeExtension
)

$ErrorActionPreference = 'Stop'

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

do {
    $reactAnswer = Read-Host 'Install React Testing Library and jsdom? (y/n)'
} until ($reactAnswer -match '^(?i:y(?:es)?|n(?:o)?)$')

$includeReactTesting = $reactAnswer -match '^(?i:y(?:es)?)$'
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

$serverTest = @'
import { describe, expect, it } from "vitest";
import request from "supertest";
import { app } from "./server";

// Update these paths once and reuse them throughout the test file.
const HEALTH_ENDPOINT_PATH = "/health";
const ITEMS_ENDPOINT_PATH = "/api/items";

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
    expect(response.body).toHaveProperty("items");
    expect(Array.isArray(response.body.items)).toBe(true);
  });
});
'@

Write-SetupFile -Path 'vitest.config.ts' -Content $vitestConfig
Write-SetupFile -Path '.prettierrc.json' -Content $prettierConfig
Write-SetupFile -Path '.prettierignore' -Content $prettierIgnore
Write-SetupFile -Path '.vscode/settings.json' -Content $vscodeSettings
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
