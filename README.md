# Interview setup tools

Small, independent PowerShell scripts. Run only the pieces you need from the target repository root. Keep this guide's `tools` folder beside the scripts.

```powershell
$setup = 'C:\Users\Admin\Repos\vitest-prettier-starter-guide'
```

| Script                   | What it does                                        | Example                                                      |
| ------------------------ | --------------------------------------------------- | ------------------------------------------------------------ |
| `setup-formatting.ps1`   | Prettier, format-on-save, format scripts            | `& "$setup\setup-formatting.ps1"`                            |
| `setup-server-tests.ps1` | Vitest with Node environment and Supertest          | `& "$setup\setup-server-tests.ps1" -ProjectDirectory server` |
| `setup-client-tests.ps1` | Vitest with jsdom and React Testing Library         | `& "$setup\setup-client-tests.ps1" -ProjectDirectory client` |
| `setup-debugging.ps1`    | Adds VS Code launch and attach choices              | `& "$setup\setup-debugging.ps1" -ProjectDirectory server`    |
| `stop-dev-processes.ps1` | Lists processes on development ports; optional stop | `& "$setup\stop-dev-processes.ps1"`                          |
| `setup-vite-types.ps1`   | Adds missing Vite CSS/asset type declarations       | `& "$setup\setup-vite-types.ps1" -ProjectDirectory client`   |

Use your actual package directory names. Omit `-ProjectDirectory` when package.json is in the current directory. The current directory should be the folder opened in VS Code; editor settings are written there.

## Formatting

Installs missing Prettier and its VS Code extension, adds missing `format` and `format:check` npm scripts, and creates missing configuration. Does not format source files during setup.

```powershell
npm run format
npm run format:check
```

Existing scripts, formatter choices, and format-on-save settings win. Language-specific VS Code overrides can also take precedence. Use `-SkipVSCodeExtension` to skip extension installation. Existing Prettier configs in the selected package are detected; parent-directory configs are not.

## Tests

Server and client use separate config files and environments. Existing `test` scripts are preserved. You write the tests; no guessed endpoints or generated failing tests are added.

- Server files: `tests/server/**/*.test.ts` (JS/JSX/TSX also supported).
- Client files: `tests/client/**/*.test.tsx` (JS/JSX/TS also supported).
- Client setup includes DOM matchers and cleanup after each test.
- Import `test`, `expect`, etc. from `vitest`; globals are not enabled.

Run within the selected package:

```powershell
npm run test:server       # watch
npm run test:server:run   # one run
npm run test:client
npm run test:client:run
```

For npm workspaces, run from the root with e.g. `npm run test:server:run -w server`. For ordinary nested packages, change into the package directory first. No tests found is expected until you write one.

The generated configs are independent of existing Vite/Vitest configuration. Copy any required aliases or plugins explicitly. Existing config files are preserved. Coverage is not installed.

## Debugging

```powershell
& "$setup\setup-debugging.ps1" -ProjectDirectory server -ScriptName dev -ClientUrl http://localhost:5173
```

In VS Code, choose **Practice: Debug server**, then F5. This runs the existing npm command in a JavaScript Debug Terminal, retaining its environment flags and watch command. Stop duplicate servers first. Alternatively, **Practice: Attach to running Node** lets you pick a process instead of assuming port 9229. A watcher restart may require reattaching.

The optional browser choice opens the supplied URL; start the frontend separately. This script does not generate a Vite proxy or rewrite npm dev scripts. Existing launch configurations and compounds are retained. Same-name configurations are left alone on subsequent runs.

## Process cleanup

```powershell
& "$setup\stop-dev-processes.ps1"                    # preview only
& "$setup\stop-dev-processes.ps1" -Ports 3001 -Stop   # stop Node on 3001
& "$setup\stop-dev-processes.ps1" -Stop -WhatIf       # describe actions
```

Default ports are 3001, 5173, and 9229. It does not know which repository owns a process: inspect the preview and narrow ports. Non-Node processes are skipped unless you add `-IncludeOtherProcesses`. Close a watch terminal if it keeps restarting its child. Windows permissions may prevent stopping another user's process.

## Before interview day

- Try the commands against a disposable copy of the actual template first.
- These helpers support npm only and refuse detected Yarn/pnpm/Bun projects.
- New test dependencies are pinned and require Node 22.22.2+, 24.15+, or 26+. Existing declared dependency versions are preserved and may need compatibility adjustments.
- Formatting and test helpers accept `-SkipInstall`: this writes configuration but does not install dependencies. It is not a dry run.
- Modified existing files get timestamped `.backup` siblings. Review those before committing.
- No setup script kills processes. The old `setup-vitest-prettier.ps1` now only prints migration guidance and exits.
- If PowerShell blocks execution, follow your machine's script policy; no helper changes that policy.
- Disable AI assistants and confirm any prewritten setup tools are permitted for your interview.

## Verification

```powershell
& "$setup\tests\setup-script.test.ps1"
```

This checks PowerShell syntax and isolated fixtures for preservation, repeated runs, JSONC comments, Vite detection, and debug configuration. It does not install packages or stop real processes. Separate disposable-project smoke checks exercised actual dependency installation and server/React tests. VS Code F5 behavior still needs a quick manual check in your target repository.

See [the quick reference](./vitest-prettier-setup-cheat-sheet.md). MIT licensed.
