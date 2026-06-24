const { createReadStream, existsSync, statSync } = require("node:fs");
const { spawn } = require("node:child_process");
const { createServer } = require("node:http");
const path = require("node:path");

const APP_DIR = __dirname;
const PLUGIN_DIR = path.resolve(APP_DIR, "..");
const PROJECT_ROOT = path.resolve(process.env.SDLC_WATCH_PROJECT_ROOT || path.resolve(APP_DIR, "../../../../.."));
const INDEXER_PATH = path.resolve(process.env.SDLC_WATCH_INDEXER_PATH || path.join(PLUGIN_DIR, "indexer.py"));
const DEFAULT_DB_PATH = path.resolve(process.env.SDLC_WATCH_DB_PATH || path.join(PLUGIN_DIR, "sdlc_watch.sqlite3"));
const DOCS_DIR = process.env.SDLC_WATCH_DOCS_DIR || "docs";
const DEFAULT_PYTHON_BIN = process.platform === "win32" ? "python" : "python3";
const PYTHON_BIN = process.env.SDLC_WATCH_PYTHON || process.env.PYTHON || DEFAULT_PYTHON_BIN;
const HOST = process.env.SDLC_WATCH_HOST || "127.0.0.1";
const PORT = Number.parseInt(process.env.SDLC_WATCH_PORT || "4173", 10);
const DIST_DIR = path.join(APP_DIR, "dist");

let activeDbPath = DEFAULT_DB_PATH;

function indexerBaseArgs() {
  return [
    INDEXER_PATH,
    "--root",
    PROJECT_ROOT,
    "--db",
    activeDbPath,
    "--docs-dir",
    DOCS_DIR,
  ];
}

function parseIndexerOutput(stdout) {
  const text = stdout.trim();
  if (!text) return { ok: false, error: "empty_output", message: "索引器没有返回 JSON。" };
  try {
    return JSON.parse(text);
  } catch (error) {
    return { ok: false, error: "invalid_json", message: error.message, raw: text.slice(0, 1200) };
  }
}

function runIndexer(command, args = []) {
  return new Promise((resolve) => {
    const child = spawn(PYTHON_BIN, [...indexerBaseArgs(), command, ...args], {
      cwd: PROJECT_ROOT,
      windowsHide: true,
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    const timer = setTimeout(() => {
      child.kill();
      resolve({ ok: false, error: "timeout", message: "索引器执行超过 30 秒。" });
    }, 30000);

    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString("utf8");
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString("utf8");
    });
    child.on("error", (error) => {
      clearTimeout(timer);
      resolve({ ok: false, error: "spawn_failed", message: error.message });
    });
    child.on("close", (code) => {
      clearTimeout(timer);
      const payload = parseIndexerOutput(stdout);
      if (!payload.ok && stderr.trim()) payload.stderr = stderr.trim().slice(0, 1200);
      if (code !== 0 && payload.ok) {
        payload.ok = false;
        payload.error = "non_zero_exit";
        payload.message = `索引器退出码 ${code}`;
      }
      resolve(payload);
    });
  });
}

function sendJson(response, statusCode, payload) {
  const body = JSON.stringify(payload);
  response.writeHead(statusCode, {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
  });
  response.end(body);
}

function readBody(request) {
  return new Promise((resolve, reject) => {
    let raw = "";
    request.on("data", (chunk) => {
      raw += chunk.toString("utf8");
      if (raw.length > 1024 * 1024) {
        reject(new Error("request body too large"));
        request.destroy();
      }
    });
    request.on("end", () => {
      if (!raw) {
        resolve({});
        return;
      }
      try {
        resolve(JSON.parse(raw));
      } catch (error) {
        reject(error);
      }
    });
    request.on("error", reject);
  });
}

function textArg(value, fallback = "") {
  return typeof value === "string" ? value : fallback;
}

function intArg(value, fallback) {
  const number = Number.parseInt(value, 10);
  return Number.isFinite(number) && number > 0 ? String(number) : String(fallback);
}

function dbPathArg(value) {
  const text = textArg(value).trim();
  return text ? path.resolve(text) : DEFAULT_DB_PATH;
}

async function handleApi(request, response, url) {
  if (request.method === "GET" && url.pathname === "/api/config") {
    sendJson(response, 200, {
      ok: true,
      projectRoot: PROJECT_ROOT,
      indexerPath: INDEXER_PATH,
      dbPath: activeDbPath,
      docsDir: DOCS_DIR,
      mode: "web",
    });
    return true;
  }
  if (request.method === "POST" && url.pathname === "/api/db-path") {
    const body = await readBody(request);
    activeDbPath = dbPathArg(body.dbPath);
    sendJson(response, 200, {
      ok: true,
      projectRoot: PROJECT_ROOT,
      indexerPath: INDEXER_PATH,
      dbPath: activeDbPath,
      docsDir: DOCS_DIR,
      mode: "web",
    });
    return true;
  }
  if (request.method === "POST" && url.pathname === "/api/reindex") {
    sendJson(response, 200, await runIndexer("index"));
    return true;
  }
  if (request.method === "GET" && url.pathname === "/api/requirements") {
    const limit = intArg(url.searchParams.get("limit"), 200);
    sendJson(response, 200, await runIndexer("list-requirements", ["--limit", limit]));
    return true;
  }
  if (request.method === "GET" && url.pathname.startsWith("/api/requirements/")) {
    const requirement = decodeURIComponent(url.pathname.slice("/api/requirements/".length));
    sendJson(response, 200, await runIndexer("get-requirement", [requirement]));
    return true;
  }
  if (request.method === "GET" && url.pathname.startsWith("/api/documents/")) {
    const document = decodeURIComponent(url.pathname.slice("/api/documents/".length));
    sendJson(response, 200, await runIndexer("get-document", [document, "--content"]));
    return true;
  }
  if (request.method === "GET" && url.pathname === "/api/search") {
    const query = url.searchParams.get("q") || "";
    const limit = intArg(url.searchParams.get("limit"), 50);
    sendJson(response, 200, await runIndexer("search", [query, "--limit", limit]));
    return true;
  }
  return false;
}

function contentType(filePath) {
  const ext = path.extname(filePath).toLowerCase();
  return {
    ".html": "text/html; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".svg": "image/svg+xml",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".ico": "image/x-icon",
  }[ext] || "application/octet-stream";
}

function serveStatic(request, response, url) {
  const rawPath = decodeURIComponent(url.pathname === "/" ? "/index.html" : url.pathname);
  const requested = path.resolve(DIST_DIR, `.${rawPath}`);
  const target = requested.startsWith(DIST_DIR) && existsSync(requested) && statSync(requested).isFile()
    ? requested
    : path.join(DIST_DIR, "index.html");
  response.writeHead(200, {
    "content-type": contentType(target),
    "cache-control": target.endsWith("index.html") ? "no-store" : "public, max-age=31536000, immutable",
  });
  createReadStream(target).pipe(response);
}

const server = createServer(async (request, response) => {
  try {
    const url = new URL(request.url || "/", `http://${request.headers.host || `${HOST}:${PORT}`}`);
    if (url.pathname.startsWith("/api/") && await handleApi(request, response, url)) return;
    serveStatic(request, response, url);
  } catch (error) {
    sendJson(response, 500, { ok: false, error: error.name, message: error.message });
  }
});

server.listen(PORT, HOST, () => {
  console.log(`SDLC Watch web server listening on http://${HOST}:${PORT}`);
  console.log(`SQLite: ${activeDbPath}`);
  console.log(`Project root: ${PROJECT_ROOT}`);
});
