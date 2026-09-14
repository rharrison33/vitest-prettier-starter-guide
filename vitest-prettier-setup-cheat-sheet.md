# Quick reference

Run from the repository root that you open in VS Code:

```powershell
$setup = 'C:\Users\Admin\Repos\vitest-prettier-starter-guide'

# Pick only what you need. Use your actual package directory names.
& "$setup\setup-formatting.ps1"
& "$setup\setup-server-tests.ps1" -ProjectDirectory server
& "$setup\setup-client-tests.ps1" -ProjectDirectory client
& "$setup\setup-debugging.ps1" -ProjectDirectory server
& "$setup\setup-vite-types.ps1" -ProjectDirectory client

# Preview first; narrow the ports before stopping anything.
& "$setup\stop-dev-processes.ps1"
& "$setup\stop-dev-processes.ps1" -Ports 3001 -Stop
```

Omit `-ProjectDirectory` if configuring the current package. Keep the scripts and `tools` folder together. See [README](./README.md) for prerequisites and preservation rules.

## Server test example

Save in `tests/server/health.test.ts` inside your server package. Adapt the import, endpoint and expected response to your application. Export the Express app separately from the file that calls `listen()`.

```ts
import { test, expect } from "vitest";
import request from "supertest";
import { app } from "../../src/app";

test("health endpoint responds", async () => {
  const response = await request(app).get("/api/health");
  expect(response.status).toBe(200);
  expect(response.body).toEqual({ ok: true });
});
```

Run `npm run test:server:run` inside the server package.

## React test example

Save in `tests/client/App.test.tsx` inside your client package. Adapt the heading and import to your actual UI.

```tsx
import { test, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import App from "../../src/App";

test("shows the heading", () => {
  render(<App />);
  expect(
    screen.getByRole("heading", { name: "Applications" }),
  ).toBeInTheDocument();
});
```

Run `npm run test:client:run` inside the client package. For interactions use `const user = userEvent.setup()` from `@testing-library/user-event`, then `await user.click(...)` or `await user.type(...)`.

## Debug checklist

1. Stop duplicate server instances.
2. Choose **Practice: Debug server** in VS Code and press F5.
3. Trigger the endpoint where your breakpoint lives.
4. If hitting the backend directly works but refreshing React does not, inspect the browser Network tab, frontend effect, and Vite proxy target.
5. For an already-running process, choose **Practice: Attach to running Node** and select the actual server, not just its watcher.

## Common assertions

```ts
expect(value).toBe(3); // primitive equality
expect(result).toEqual({ ok: true }); // deep equality
expect(items).toHaveLength(2);
expect(items).toContainEqual({ id: "1" });
expect(() => validate(null)).toThrow();
```
