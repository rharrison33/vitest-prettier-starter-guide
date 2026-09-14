const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const {
  run,
  jsonc,
  addProperties,
  appendConfigurations,
} = require("../tools/setup.cjs");
function fixture(work) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "practice-setup-"));
  const write = (name, content) => {
    const file = path.join(root, name);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(
      file,
      typeof content === "string" ? content : JSON.stringify(content),
    );
  };
  const read = (name) => fs.readFileSync(path.join(root, name), "utf8");
  write("package.json", {
    name: "fixture",
    private: true,
    scripts: {
      dev: "tsx watch --inspect=9230 --env-file=.env src/index.ts",
      test: "existing-test-command",
      format: "existing-formatter",
    },
    dependencies: { react: "19.2.0", vite: "7.1.7" },
  });
  try {
    work({ root, write, read });
  } finally {
    const resolved = fs.realpathSync(root);
    assert.equal(
      path.dirname(resolved).toLowerCase(),
      fs.realpathSync(os.tmpdir()).toLowerCase(),
    );
    assert(path.basename(resolved).startsWith("practice-setup-"));
    fs.rmSync(resolved, { recursive: true, force: true });
  }
}
test("JSONC edits retain comments, strings, trailing commas, unicode and existing settings", () => {
  const source =
    '{\n// hello 😀\n"url":"http://localhost:5173/a,}", /* keep */\n"editor.formatOnSave":false, // keep false\n}';
  const result = addProperties(source, {
    "editor.formatOnSave": true,
    "editor.defaultFormatter": "prettier",
  });
  assert(result.includes("// hello 😀"));
  assert(result.includes("/* keep */"));
  assert.equal(jsonc(result).value["editor.formatOnSave"], false);
  assert.equal(jsonc(result).value.url, "http://localhost:5173/a,}");
  assert.equal(
    addProperties(result, { "editor.defaultFormatter": "prettier" }),
    result,
  );
  const launch =
    '{"nested":{"configurations":[]},"configurations":[{"name":"Mine"}, /* note */],}';
  const updated = appendConfigurations(launch, [{ name: "New" }]);
  assert.deepEqual(
    jsonc(updated).value.configurations.map((c) => c.name),
    ["New", "Mine"],
  );
  assert.deepEqual(jsonc(updated).value.nested.configurations, []);
  assert.equal(appendConfigurations(updated, [{ name: "New" }]), updated);
});
test("formatting preserves scripts/dependencies/configs and is repeat-safe", () =>
  fixture(({ root, write, read }) => {
    write(".prettierrc.yaml", "semi: false\n");
    write(
      ".vscode/settings.json",
      '{ // custom\n "editor.formatOnSave":false,\n "[typescript]":{"editor.defaultFormatter":"other"},\n}',
    );
    run("formatting", { root, skipInstall: true });
    const pkg = JSON.parse(read("package.json"));
    assert.equal(pkg.scripts.format, "existing-formatter");
    assert.equal(pkg.scripts.test, "existing-test-command");
    assert.equal(pkg.scripts["format:check"], "prettier --check .");
    assert(!fs.existsSync(path.join(root, ".prettierrc.json")));
    assert.equal(
      jsonc(read(".vscode/settings.json")).value["editor.formatOnSave"],
      false,
    );
    const before = read("package.json");
    const settings = read(".vscode/settings.json");
    run("formatting", { root, skipInstall: true });
    assert.equal(read("package.json"), before);
    assert.equal(read(".vscode/settings.json"), settings);
  }));
test("server/client setup stays isolated and preserves unrelated tests", () =>
  fixture(({ root, write, read }) => {
    write("server/package.json", { name: "server", private: true });
    write("client/package.json", {
      name: "client",
      private: true,
      dependencies: { react: "19.2.0" },
    });
    run("server-tests", { root, project: "server", skipInstall: true });
    run("client-tests", { root, project: "client", skipInstall: true });
    assert(
      read("server/vitest.server.config.mts").includes('environment: "node"'),
    );
    assert(
      read("client/vitest.client.config.mts").includes('environment: "jsdom"'),
    );
    assert(read("client/tests/client/setup.ts").includes("afterEach(cleanup)"));
    assert.equal(
      JSON.parse(read("package.json")).scripts.test,
      "existing-test-command",
    );
    assert(!fs.existsSync(path.join(root, "server.test.ts")));
    const before = read("client/vitest.client.config.mts");
    run("client-tests", { root, project: "client", skipInstall: true });
    assert.equal(read("client/vitest.client.config.mts"), before);
  }));
test("debugging merges launch entries and preserves exact startup command including custom inspector", () =>
  fixture(({ root, write, read }) => {
    write(
      ".vscode/launch.json",
      '{ // debugger\n"version":"0.2.0","configurations":[{"name":"Original","port":9230},],"compounds":[]}',
    );
    const original = read("package.json");
    run("debugging", { root, clientUrl: "http://localhost:5180" });
    const launch = jsonc(read(".vscode/launch.json")).value;
    assert(
      launch.configurations.some(
        (c) => c.name === "Original" && c.port === 9230,
      ),
    );
    assert.equal(
      launch.configurations.find((c) => c.type === "node-terminal").command,
      "npm run dev",
    );
    assert.equal(
      launch.configurations.find((c) => c.type === "node").processId,
      "${command:PickProcess}",
    );
    assert.equal(
      launch.configurations.find((c) => c.type === "chrome").url,
      "http://localhost:5180/",
    );
    assert.equal(read("package.json"), original);
    const before = read(".vscode/launch.json");
    run("debugging", { root, clientUrl: "http://localhost:5180" });
    assert.equal(read(".vscode/launch.json"), before);
  }));
test("Vite source/root declarations are only created if missing", () =>
  fixture(({ root, write, read }) => {
    write("src/App.tsx", "export default () => null;");
    run("vite-types", { root });
    assert(read("src/vite-env.d.ts").includes("vite/client"));
    write("src/vite-env.d.ts", "// custom");
    run("vite-types", { root });
    assert.equal(read("src/vite-env.d.ts"), "// custom");
    write("plain/package.json", { name: "plain" });
    run("vite-types", { root, project: "plain" });
    assert(!fs.existsSync(path.join(root, "plain/vite-env.d.ts")));
    write("web/package.json", { devDependencies: { vite: "7.1.7" } });
    run("vite-types", { root, project: "web" });
    assert(read("web/vite-env.d.ts").includes("vite/client"));
  }));
test("bad config and unsupported package managers fail before writing setup", () =>
  fixture(({ root, write, read }) => {
    write(".vscode/settings.json", "{broken");
    const before = read("package.json");
    assert.throws(() => run("formatting", { root, skipInstall: true }));
    assert.equal(read("package.json"), before);
    assert(!fs.existsSync(path.join(root, ".prettierrc.json")));
    write("pnpm-lock.yaml", "lockfileVersion: 9");
    assert.throws(
      () => run("server-tests", { root, skipInstall: true }),
      /Non-npm/,
    );
    assert(!fs.existsSync(path.join(root, "vitest.server.config.mts")));
  }));
