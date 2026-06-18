const { app, BrowserWindow, ipcMain, Menu } = require("electron");
const { spawn } = require("node:child_process");
const path = require("node:path");

const APP_DIR = __dirname;
const PLUGIN_DIR = path.resolve(APP_DIR, "..");
const PROJECT_ROOT = path.resolve(APP_DIR, "../../../../..");
const INDEXER_PATH = path.join(PLUGIN_DIR, "indexer.py");
const DEFAULT_DB_PATH = path.join(PLUGIN_DIR, "sdlc_watch.sqlite3");
const PYTHON_BIN = process.env.SDLC_WATCH_PYTHON || process.env.PYTHON || "python";

let mainWindow = null;
let activeDbPath = process.env.SDLC_WATCH_DB_PATH || DEFAULT_DB_PATH;

// 自动化 UI 验证时暴露 Chromium 调试端口，正常启动不启用。
if (process.env.SDLC_WATCH_REMOTE_DEBUGGING_PORT) {
  app.commandLine.appendSwitch("remote-debugging-port", process.env.SDLC_WATCH_REMOTE_DEBUGGING_PORT);
}

function indexerBaseArgs() {
  return [
    INDEXER_PATH,
    "--root",
    PROJECT_ROOT,
    "--db",
    activeDbPath,
    "--docs-dir",
    process.env.SDLC_WATCH_DOCS_DIR || "docs",
  ];
}

function parseIndexerOutput(stdout) {
  const text = stdout.trim();
  if (!text) {
    return { ok: false, error: "empty_output", message: "索引器没有返回 JSON。" };
  }
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
      if (!payload.ok && stderr.trim()) {
        payload.stderr = stderr.trim().slice(0, 1200);
      }
      if (code !== 0 && payload.ok) {
        payload.ok = false;
        payload.error = "non_zero_exit";
        payload.message = `索引器退出码 ${code}`;
      }
      resolve(payload);
    });
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

function registerIpcHandlers() {
  ipcMain.handle("sdlc-watch:config", async () => ({
    ok: true,
    projectRoot: PROJECT_ROOT,
    indexerPath: INDEXER_PATH,
    dbPath: activeDbPath,
    docsDir: process.env.SDLC_WATCH_DOCS_DIR || "docs",
  }));

  ipcMain.handle("sdlc-watch:set-db-path", async (_event, dbPath) => {
    activeDbPath = dbPathArg(dbPath);
    return {
      ok: true,
      dbPath: activeDbPath,
      projectRoot: PROJECT_ROOT,
      indexerPath: INDEXER_PATH,
      docsDir: process.env.SDLC_WATCH_DOCS_DIR || "docs",
    };
  });

  ipcMain.handle("sdlc-watch:reindex", async () => runIndexer("index"));
  ipcMain.handle("sdlc-watch:list-requirements", async (_event, limit) => {
    return runIndexer("list-requirements", ["--limit", intArg(limit, 200)]);
  });
  ipcMain.handle("sdlc-watch:get-requirement", async (_event, requirement) => {
    return runIndexer("get-requirement", [textArg(requirement)]);
  });
  ipcMain.handle("sdlc-watch:get-document", async (_event, document) => {
    return runIndexer("get-document", [textArg(document), "--content"]);
  });
  ipcMain.handle("sdlc-watch:search", async (_event, query, limit) => {
    return runIndexer("search", [textArg(query), "--limit", intArg(limit, 50)]);
  });
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1360,
    height: 860,
    minWidth: 1040,
    minHeight: 680,
    backgroundColor: "#f8fafc",
    title: "SDLC Watch",
    webPreferences: {
      preload: path.join(APP_DIR, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,
    },
  });

  const devUrl = process.env.SDLC_WATCH_DEV_URL;
  if (devUrl) {
    mainWindow.loadURL(devUrl);
    return;
  }
  mainWindow.loadFile(path.join(APP_DIR, "dist", "index.html"));
}

function openIndexDialog() {
  if (!mainWindow || mainWindow.isDestroyed()) return;
  mainWindow.webContents.send("sdlc-watch:open-index-dialog");
}

function buildApplicationMenu() {
  return Menu.buildFromTemplate([
    {
      label: "索引",
      submenu: [
        {
          label: "更新索引...",
          accelerator: "CommandOrControl+Shift+U",
          click: openIndexDialog,
        },
      ],
    },
    {
      label: "窗口",
      role: "windowMenu",
    },
  ]);
}

app.whenReady().then(() => {
  registerIpcHandlers();
  createWindow();
  Menu.setApplicationMenu(buildApplicationMenu());
  // 冒烟测试专用开关，正常启动不会触发。
  if (process.env.SDLC_WATCH_SMOKE_EXIT === "1") {
    setTimeout(() => app.quit(), 1500);
  }
  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow();
    }
  });
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") {
    app.quit();
  }
});
