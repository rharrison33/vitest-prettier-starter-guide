# Vitest + Prettier Setup Cheat Sheet

Use these steps from the root of a new JavaScript or React project.

## 1. Install the packages

```powershell
npm install --save-dev vitest prettier
```

For API tests with Express, also install Supertest:

```powershell
npm install --save-dev supertest
```

For React component tests, install the browser-like test environment and Testing Library:

```powershell
npm install --save-dev jsdom @testing-library/react @testing-library/jest-dom
```

## 2. Add package scripts

```powershell
npm pkg set 'scripts.test=vitest'
npm pkg set 'scripts.test:run=vitest --run'
npm pkg set 'scripts.test:coverage=vitest --coverage'
npm pkg set 'scripts.format=prettier --write .'
npm pkg set 'scripts.format:check=prettier --check .'
```

Install the coverage provider only if you plan to run coverage:

```powershell
npm install --save-dev @vitest/coverage-v8
```

## 3. Create a Vitest configuration

For Node/server tests:

```powershell
@'
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "node",
    globals: true,
  },
});
'@ | Set-Content vitest.config.js
```

For React/browser-oriented tests, use `jsdom` instead:

```javascript
test: {
  environment: "jsdom",
  globals: true,
}
```

If the project uses CommonJS rather than ES modules, name the configuration `vitest.config.mjs`, or add this to `package.json`:

```json
{
  "type": "module"
}
```

## 4. Write a first test

Create `example.test.js`:

```powershell
@'
import { describe, expect, it } from "vitest";

describe("example", () => {
  it("adds two numbers", () => {
    expect(2 + 2).toBe(4);
  });
});
'@ | Set-Content example.test.js
```

Run tests in watch mode:

```powershell
npm test
```

Run tests once, which is useful before committing or in CI:

```powershell
npm run test:run
```

## 5. Configure Prettier

Create `.prettierrc.json`:

```powershell
@'
{
  "semi": true,
  "singleQuote": false,
  "tabWidth": 2,
  "trailingComma": "es5"
}
'@ | Set-Content .prettierrc.json
```

Create `.prettierignore`:

```powershell
@'
node_modules
dist
build
coverage
package-lock.json
'@ | Set-Content .prettierignore
```

Format the project:

```powershell
npm run format
```

Check formatting without changing files:

```powershell
npm run format:check
```

## 6. Enable format-on-save in VS Code

Install the Prettier extension:

```powershell
code --install-extension esbenp.prettier-vscode
New-Item -ItemType Directory -Force .vscode
```

Create `.vscode/settings.json`:

```powershell
@'
{
  "editor.defaultFormatter": "esbenp.prettier-vscode",
  "editor.formatOnSave": true,
  "[javascript]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode"
  },
  "[javascriptreact]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode"
  },
  "[json]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode"
  }
}
'@ | Set-Content .vscode/settings.json
```

## 7. Verify everything

```powershell
npm run format
npm run test:run
git status --short
```

## Common Vitest matchers

```javascript
expect(value).toBe(expected);
expect(object).toEqual(expectedObject);
expect(value).toBeTruthy();
expect(value).toBeFalsy();
expect(array).toHaveLength(3);
expect(array).toContain(item);
expect(string).toContain("text");
expect(fn).toThrow();
await expect(promise).resolves.toEqual(expected);
await expect(promise).rejects.toThrow();
```

Remember that `expect(value)` alone does not assert anything. Always call a matcher:

```javascript
expect(result).toBe(true);
```

## Notes

- Commands using `Set-Content` overwrite existing files. Merge settings manually if the project already has those configuration files.
- Use `npm test` while developing because Vitest watches for changes.
- Use `npm run test:run` for a single test run.
- Keep tests close to the code (`thing.test.js`) or place them in a dedicated `tests` directory.
- Commit configuration files so every contributor uses the same setup.
