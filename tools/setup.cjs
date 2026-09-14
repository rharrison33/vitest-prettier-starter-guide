const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

// Parse VS Code JSONC without rewriting comments or unrelated settings.
function jsonc(text) {
  let clean = "",
    quoted = false,
    escaped = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      clean += c;
      if (escaped) escaped = false;
      else if (c === "\\") escaped = true;
      else if (c === '"') quoted = false;
    } else if (c === '"') {
      quoted = true;
      clean += c;
    } else if (c === "/" && text[i + 1] === "/") {
      while (i < text.length && text[i] !== "\n") {
        clean += " ";
        i++;
      }
      if (i < text.length) clean += "\n";
    } else if (c === "/" && text[i + 1] === "*") {
      clean += "  ";
      i += 2;
      while (i < text.length && !(text[i] === "*" && text[i + 1] === "/")) {
        clean += text[i] === "\n" ? "\n" : " ";
        i++;
      }
      if (i >= text.length) throw new Error("Unclosed JSON comment.");
      clean += "  ";
      i++;
    } else if (c === "," && /^\s*[}\]]/.test(text.slice(i + 1))) clean += " ";
    else clean += c === "\ufeff" ? " " : c;
  }
  // Remove trailing commas followed by comments, which are now whitespace.
  quoted = false;
  escaped = false;
  const chars = clean.split("");
  for (let i = 0; i < chars.length; i++) {
    const c = chars[i];
    if (quoted) {
      if (escaped) escaped = false;
      else if (c === "\\") escaped = true;
      else if (c === '"') quoted = false;
    } else if (c === '"') quoted = true;
    else if (c === "," && /^\s*[}\]]/.test(chars.slice(i + 1).join("")))
      chars[i] = " ";
  }
  clean = chars.join("");
  return { value: JSON.parse(clean), clean };
}
function object(text) {
  const parsed = jsonc(text);
  if (
    !parsed.value ||
    Array.isArray(parsed.value) ||
    typeof parsed.value !== "object"
  )
    throw new Error("Expected a JSON object.");
  return parsed;
}
function addProperties(text, additions) {
  const { value, clean } = object(text);
  const missing = Object.entries(additions).filter(([key, expected]) => {
    if (!(key in value)) return true;
    if (JSON.stringify(value[key]) !== JSON.stringify(expected))
      console.log(`Preserved existing setting: ${key}`);
    return false;
  });
  if (!missing.length) return text;
  const insert = missing
    .map(([k, v]) => `  ${JSON.stringify(k)}: ${JSON.stringify(v, null, 2)}`)
    .join(",\n");
  const pos = clean.indexOf("{") + 1;
  return (
    text.slice(0, pos) +
    "\n" +
    insert +
    (Object.keys(value).length ? "," : "") +
    "\n" +
    text.slice(pos)
  );
}
function appendConfigurations(text, additions) {
  const { value, clean } = object(text);
  if (!("configurations" in value))
    return addProperties(text, { configurations: additions });
  if (!Array.isArray(value.configurations))
    throw new Error("launch.json configurations must be an array.");
  const missing = additions.filter(
    (a) => !value.configurations.some((c) => c.name === a.name),
  );
  if (!missing.length) return text;
  let depth = 0,
    start = -1;
  for (let i = 0; i < clean.length; i++) {
    if (clean[i] === '"') {
      const token = /^"(?:\\.|[^"\\])*"/.exec(clean.slice(i));
      if (!token) throw new Error("Invalid JSON string.");
      if (
        depth === 1 &&
        JSON.parse(token[0]) === "configurations" &&
        /^\s*:/.test(clean.slice(i + token[0].length))
      ) {
        start = clean.indexOf("[", i + token[0].length);
        break;
      }
      i += token[0].length - 1;
    } else if ("{[".includes(clean[i])) depth++;
    else if ("}]".includes(clean[i])) depth--;
  }
  if (start < 0) throw new Error("Cannot locate configurations array.");
  const content = missing.map((c) => JSON.stringify(c, null, 2)).join(",\n");
  return (
    text.slice(0, start + 1) +
    "\n" +
    content +
    (value.configurations.length ? "," : "") +
    "\n" +
    text.slice(start + 1)
  );
}
function run(action, options = {}) {
  const root = path.resolve(options.root || process.cwd());
  const project = path.resolve(root, options.project || ".");
  const packagePath = path.join(project, "package.json");
  if (!fs.existsSync(packagePath))
    throw new Error(
      `No package.json at ${packagePath}. Set -ProjectDirectory to the package you want to configure.`,
    );
  const pkg = JSON.parse(
    fs.readFileSync(packagePath, "utf8").replace(/^\ufeff/, ""),
  );
  // Do not silently introduce npm into a pnpm/Yarn/Bun repository.
  for (let dir = project; ; dir = path.dirname(dir)) {
    const manifest = path.join(dir, "package.json");
    if (fs.existsSync(manifest)) {
      const parent = JSON.parse(
        fs.readFileSync(manifest, "utf8").replace(/^\ufeff/, ""),
      );
      if (parent.packageManager && !parent.packageManager.startsWith("npm@"))
        throw new Error(
          `This project uses ${parent.packageManager}; these setup scripts support npm only.`,
        );
    }
    if (
      ["pnpm-lock.yaml", "yarn.lock", "bun.lock", "bun.lockb"].some((f) =>
        fs.existsSync(path.join(dir, f)),
      )
    )
      throw new Error(
        `Non-npm lockfile in ${dir}. Use that project's package manager instead.`,
      );
    if (path.dirname(dir) === dir || fs.existsSync(path.join(dir, ".git")))
      break;
  }
  const plans = new Map();
  const get = (file) =>
    plans.get(file) ??
    (fs.existsSync(file) ? fs.readFileSync(file, "utf8") : "{}\n");
  const fresh = (file, content) => {
    if (!fs.existsSync(file)) plans.set(file, content.trim() + "\n");
    else console.log(`Preserved: ${path.relative(root, file)}`);
  };
  const scripts = {};
  const requirements = {};
  if (action === "formatting") {
    requirements.prettier = "3.9.6";
    scripts.format = "prettier --write .";
    scripts["format:check"] = "prettier --check .";
    const hasConfig =
      pkg.prettier !== undefined ||
      fs
        .readdirSync(project)
        .some(
          (f) =>
            f === ".prettierrc" ||
            f.startsWith(".prettierrc.") ||
            /^prettier\.config\./.test(f),
        );
    if (!hasConfig)
      fresh(
        path.join(project, ".prettierrc.json"),
        '{"semi":true,"singleQuote":false,"tabWidth":2,"trailingComma":"es5"}',
      );
    fresh(
      path.join(project, ".prettierignore"),
      "node_modules\ndist\nbuild\ncoverage\npackage-lock.json\n",
    );
    const file = path.join(root, ".vscode/settings.json");
    plans.set(
      file,
      addProperties(get(file), {
        "editor.defaultFormatter": "esbenp.prettier-vscode",
        "editor.formatOnSave": true,
      }),
    );
  } else if (action === "server-tests" || action === "client-tests") {
    const client = action === "client-tests";
    if (client && !(pkg.dependencies?.react || pkg.devDependencies?.react))
      throw new Error(
        "No React dependency in this package. Pass -ProjectDirectory client (or the actual frontend directory).",
      );
    requirements.vitest = "5.0.0";
    if (client)
      Object.assign(requirements, {
        jsdom: "30.0.1",
        "@testing-library/react": "16.3.3",
        "@testing-library/jest-dom": "7.0.1",
        "@testing-library/user-event": "14.6.1",
      });
    else
      Object.assign(requirements, {
        supertest: "7.2.2",
        "@types/supertest": "7.2.1",
      });
    const kind = client ? "client" : "server";
    let vitestMajor = Number(
      String(
        pkg.devDependencies?.vitest ||
          pkg.dependencies?.vitest ||
          requirements.vitest,
      ).match(/\d+/)?.[0] || 5,
    );
    try {
      vitestMajor = Number(
        JSON.parse(
          fs.readFileSync(
            require.resolve("vitest/package.json", { paths: [project] }),
            "utf8",
          ),
        ).version.split(".")[0],
      );
    } catch {
      /* Not installed yet; use the declared version. */
    }
    const config = `vitest.${kind}.config.mts`;
    scripts[`test:${kind}`] = `vitest --config ${config}`;
    scripts[`test:${kind}:run`] = `vitest run --config ${config}`;
    fresh(
      path.join(project, config),
      `import { defineConfig } from "vitest/config";
export default defineConfig({
  ${client ? (vitestMajor >= 5 ? 'oxc: { jsx: { runtime: "automatic" } },' : 'esbuild: { jsx: "automatic" },') : ""}
  test: {
    environment: "${client ? "jsdom" : "node"}",
    include: ["tests/${kind}/**/*.test.{ts,tsx,js,jsx}"],
    ${client ? 'setupFiles: ["./tests/client/setup.ts"],' : ""}
  },
});`,
    );
    if (client)
      fresh(
        path.join(project, "tests/client/setup.ts"),
        'import "@testing-library/jest-dom/vitest";\nimport { afterEach } from "vitest";\nimport { cleanup } from "@testing-library/react";\nafterEach(cleanup);',
      );
    console.log(
      `Put your own tests in ${path.join(project, "tests", kind)}. No guessed endpoint tests are generated.`,
    );
    console.log(
      "These configs are independent of existing Vite/Vitest configs. Copy any required aliases/plugins explicitly.",
    );
  } else if (action === "debugging") {
    const script = options.script || "dev";
    if (!/^[\w:.-]+$/.test(script))
      throw new Error("Use a simple npm script name.");
    if (!pkg.scripts?.[script])
      throw new Error(
        `No npm script named ${script} in ${packagePath}. Use -ScriptName.`,
      );
    const relative = path.relative(root, project).replaceAll("\\", "/");
    if (
      relative === ".." ||
      relative.startsWith("../") ||
      path.isAbsolute(relative)
    )
      throw new Error(
        "The debug package must be inside the current VS Code workspace root.",
      );
    const entries = [
      {
        name: "Practice: Debug server",
        type: "node-terminal",
        request: "launch",
        command: `npm run ${script}`,
        cwd: "${workspaceFolder}" + (relative ? "/" + relative : ""),
      },
      {
        name: "Practice: Attach to running Node",
        type: "node",
        request: "attach",
        processId: "${command:PickProcess}",
        skipFiles: ["<node_internals>/**"],
      },
    ];
    if (options.clientUrl) {
      const url = new URL(options.clientUrl);
      if (!["http:", "https:"].includes(url.protocol))
        throw new Error("Client URL must be http or https.");
      entries.push({
        name: "Practice: Debug browser",
        type: "chrome",
        request: "launch",
        url: url.href,
        webRoot: "${workspaceFolder}",
      });
    }
    const file = path.join(root, ".vscode/launch.json");
    plans.set(
      file,
      appendConfigurations(
        addProperties(get(file), { version: "0.2.0" }),
        entries,
      ),
    );
    console.log(
      "F5 with Practice: Debug server starts your existing npm command in a JavaScript Debug Terminal. Stop any duplicate server first.",
    );
    console.log(
      "For an already running server, choose Practice: Attach to running Node and select its process. Start the frontend separately; no proxy is generated.",
    );
  } else if (action === "vite-types") {
    if (!(pkg.dependencies?.vite || pkg.devDependencies?.vite)) {
      console.log("No Vite dependency in this package; nothing changed.");
      return;
    }
    const src = path.join(project, "src");
    if (
      ![
        path.join(project, "vite-env.d.ts"),
        path.join(src, "vite-env.d.ts"),
      ].some(fs.existsSync)
    )
      fresh(
        path.join(
          fs.existsSync(src) && fs.statSync(src).isDirectory() ? src : project,
          "vite-env.d.ts",
        ),
        '/// <reference types="vite/client" />',
      );
  } else throw new Error(`Unknown setup action: ${action}`);

  // Validate JSONC and all edits before installing anything.
  for (const [file, text] of plans) if (file.endsWith(".json")) object(text);
  const missing = Object.entries(requirements).filter(
    ([name]) => !pkg.dependencies?.[name] && !pkg.devDependencies?.[name],
  );
  if (missing.length && !options.skipInstall) {
    const [major, minor, patch] = process.versions.node.split(".").map(Number);
    if (
      action.endsWith("-tests") &&
      !(
        (major === 22 && (minor > 22 || (minor === 22 && patch >= 2))) ||
        (major === 24 && minor >= 15) ||
        major >= 26
      )
    )
      throw new Error(
        "New test dependencies require Node 22.22.2+, 24.15+, or 26+. Use a supported LTS version before setup.",
      );
    const npmCli = [
      path.dirname(process.execPath),
      ...(process.env.PATH || "").split(path.delimiter),
    ]
      .map((dir) => path.join(dir, "node_modules/npm/bin/npm-cli.js"))
      .find((file) => fs.existsSync(file));
    if (!npmCli)
      throw new Error(
        "Could not locate npm-cli.js beside Node/npm on PATH. Install standard Node.js with npm, or install the listed dependencies manually and rerun with -SkipInstall.",
      );
    const result = spawnSync(
      process.execPath,
      [
        npmCli,
        "install",
        "--save-dev",
        "--save-exact",
        ...missing.map(([n, v]) => `${n}@${v}`),
      ],
      { cwd: project, stdio: "inherit" },
    );
    if (result.error || result.status !== 0)
      throw new Error(
        "npm install failed. No setup configs were written. Check npm output and any package/lockfile changes.",
      );
  } else if (missing.length)
    console.log(
      `Skipped installation (configuration-only): ${missing.map(([n, v]) => `${n}@${v}`).join(" ")}`,
    );
  // Read again after npm to keep its dependency/lockfile changes.
  const manifestText = fs.readFileSync(packagePath, "utf8");
  const current = JSON.parse(manifestText.replace(/^\ufeff/, ""));
  let changed = false;
  for (const [name, command] of Object.entries(scripts)) {
    current.scripts ??= {};
    if (name in current.scripts) {
      console.log(`Preserved npm script: ${name}`);
      continue;
    }
    current.scripts[name] = command;
    changed = true;
  }
  if (changed) plans.set(packagePath, JSON.stringify(current, null, 2) + "\n");
  for (const [file, text] of plans) {
    if (fs.existsSync(file) && fs.readFileSync(file, "utf8") === text) continue;
    fs.mkdirSync(path.dirname(file), { recursive: true });
    if (fs.existsSync(file))
      fs.copyFileSync(file, file + "." + Date.now() + ".backup");
    fs.writeFileSync(file, text);
    console.log(`Updated: ${path.relative(root, file)}`);
  }
  console.log(
    "Done. Existing dependency versions, scripts, and settings were preserved.",
  );
}
module.exports = { jsonc, addProperties, appendConfigurations, run };
if (require.main === module) {
  try {
    run(
      process.argv[2],
      JSON.parse(fs.readFileSync(0, "utf8").replace(/^\ufeff/, "") || "{}"),
    );
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
