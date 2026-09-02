# Vitest + Prettier Setup Cheat Sheet

Use these steps from the root of a new TypeScript, JavaScript, or React project. For a TypeScript server, prefer test filenames such as `server.test.ts`.

## 1. Install the packages

```powershell
npm install --save-dev vitest prettier
```

For API tests with Express, also install Supertest:

```powershell
npm install --save-dev supertest @types/supertest
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
'@ | Set-Content vitest.config.ts
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

## 4. Write a first server test

Create `server.test.ts`. This example assumes the Express app is exported from `server.ts` without immediately calling `listen()`:

```powershell
@'
import { describe, expect, it } from "vitest";
import request from "supertest";
import { app } from "./server";

describe("GET /health", () => {
  it("returns a successful health response", async () => {
    const response = await request(app).get("/health");

    expect(response.status).toBe(200);
  });
});

describe("GET /api/items", () => {
  it("returns a successful response", async () => {
    const response = await request(app).get("/api/items");

    expect(response.status).toBe(200);
    expect(response.body).toHaveProperty("items");
    expect(Array.isArray(response.body.items)).toBe(true);
  });
});
'@ | Set-Content server.test.ts
```

If `server.ts` starts the listener itself, separate the Express app from the startup code so tests can import it without opening a network port:

```typescript
// app.ts
import express, { type Express } from "express";

export const app: Express = express();
app.use(express.json());
```

```typescript
// server.ts
import { app } from "./app";

app.listen(3000, () => {
  console.log("Server listening on port 3000");
});
```

The test would then import `app` from `./app`.

Run tests in watch mode:

```powershell
npm test
```

Run tests once, which is useful before committing or in CI:

```powershell
npm run test:run
```

## 5. Useful server test patterns

### Parameterized tests with `it.each`

Use `it.each` when the same behavior should be checked with several inputs. This keeps validation and boundary tests concise.

```typescript
describe("GET /api/items query validation", () => {
  it.each([
    ["page=0", "page must be a positive integer"],
    ["page=-1", "page must be a positive integer"],
    ["page=1.5", "page must be a positive integer"],
    ["page=abc", "page must be a positive integer"],
  ])("rejects ?%s", async (query, expectedError) => {
    const response = await request(app).get(`/api/items?${query}`);

    expect(response.status).toBe(400);
    expect(response.body).toMatchObject({ error: expectedError });
  });
});
```

An object table is easier to read when each case has several values:

```typescript
describe("GET /api/items price filters", () => {
  it.each([
    { query: "minPrice=10", expectedStatus: 200 },
    { query: "maxPrice=100", expectedStatus: 200 },
    { query: "minPrice=-1", expectedStatus: 400 },
    {
      query: "minPrice=100&maxPrice=10",
      expectedStatus: 400,
    },
  ])("returns $expectedStatus for $query", async ({
    query,
    expectedStatus,
  }) => {
    const response = await request(app).get(`/api/items?${query}`);

    expect(response.status).toBe(expectedStatus);
  });
});
```

### Check the response contract

Do not check only the status code. Verify the important fields and types without making the test unnecessarily brittle.

```typescript
it("returns the expected item response shape", async () => {
  const response = await request(app).get("/api/items");

  expect(response.status).toBe(200);
  expect(response.body).toEqual(
    expect.objectContaining({
      items: expect.any(Array),
      totalCount: expect.any(Number),
      page: expect.any(Number),
      pageSize: expect.any(Number),
    })
  );
});
```

Check an individual item when the endpoint returns data:

```typescript
it("returns correctly shaped items", async () => {
  const response = await request(app).get("/api/items");
  const firstItem: unknown = response.body.items[0];

  expect(firstItem).toEqual(
    expect.objectContaining({
      id: expect.any(String),
      name: expect.any(String),
      price: expect.any(Number),
      category: expect.any(String),
    })
  );
});
```

### Search tests

Cover normalization and the intended matching behavior. Do not test typo tolerance unless fuzzy search is actually required.

```typescript
describe("GET /api/items search", () => {
  it.each(["widget", "WIDGET", "  widget  "])(
    "finds an item using search=%j",
    async (search) => {
      const response = await request(app)
        .get("/api/items")
        .query({ search });

      expect(response.status).toBe(200);
      expect(response.body.items).toEqual(
        expect.arrayContaining([
          expect.objectContaining({ name: "Example Widget" }),
        ])
      );
    }
  );

  it("returns an empty array when nothing matches", async () => {
    const response = await request(app)
      .get("/api/items")
      .query({ search: "no-such-item" });

    expect(response.status).toBe(200);
    expect(response.body.items).toEqual([]);
    expect(response.body.totalCount).toBe(0);
  });
});
```

Using Supertest's `.query()` is safer and clearer than manually building query strings because it handles URL encoding.

### Pagination tests

Test boundaries and metadata, not just the happy path.

```typescript
describe("GET /api/items pagination", () => {
  it("returns the requested page size", async () => {
    const response = await request(app)
      .get("/api/items")
      .query({ page: 1, pageSize: 2 });

    expect(response.status).toBe(200);
    expect(response.body.items.length).toBeLessThanOrEqual(2);
    expect(response.body.page).toBe(1);
    expect(response.body.pageSize).toBe(2);
  });

  it("returns an empty list for a page beyond the results", async () => {
    const response = await request(app)
      .get("/api/items")
      .query({ page: 9999, pageSize: 25 });

    expect(response.status).toBe(200);
    expect(response.body.items).toEqual([]);
  });
});
```

### Arrange, Act, Assert

Keep each test easy to scan:

```typescript
it("filters items by category", async () => {
  // Arrange
  const category = "hardware";

  // Act
  const response = await request(app)
    .get("/api/items")
    .query({ category });

  // Assert
  expect(response.status).toBe(200);
  expect(response.body.items).toEqual(
    expect.arrayContaining([
      expect.objectContaining({ category: "hardware" }),
    ])
  );
});
```

The comments are useful while learning but can be omitted when the sections are already obvious.

### Test setup and isolation

Use hooks when tests need known data or cleanup:

```typescript
import { beforeEach, describe, expect, it } from "vitest";

describe("item routes", () => {
  beforeEach(() => {
    // Reset the in-memory store or seed known test data.
  });

  it("does not depend on another test running first", async () => {
    const response = await request(app).get("/api/items");

    expect(response.status).toBe(200);
  });
});
```

Good tests should:

- Have descriptive names that state the expected behavior.
- Test one behavior at a time.
- Cover happy paths, invalid input, boundaries, and empty results.
- Use fixed, predictable test data instead of random Faker output.
- Avoid depending on test execution order.
- Prefer observable behavior over internal implementation details.
- Check exact values when they matter and flexible shapes when incidental values may change.
- Avoid snapshots for simple API responses; focused assertions explain failures better.

## 6. Configure Prettier

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

## 7. Enable format-on-save in VS Code

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
'@ | Set-Content .vscode/settings.json
```

## 8. Verify everything

```powershell
npm run format
npm run test:run
git status --short
```

## Common Vitest matchers

```typescript
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

```typescript
expect(result).toBe(true);
```

## Notes

- Commands using `Set-Content` overwrite existing files. Merge settings manually if the project already has those configuration files.
- Use `npm test` while developing because Vitest watches for changes.
- Use `npm run test:run` for a single test run.
- Use `.test.ts` for TypeScript server tests and `.test.tsx` for React component tests.
- Keep tests close to the code (`thing.test.ts`) or place them in a dedicated `tests` directory.
- Commit configuration files so every contributor uses the same setup.
