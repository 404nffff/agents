const http = require("http");
const fs = require("fs");
const path = require("path");

const HOST = process.env.HOST || "0.0.0.0";
const PORT = Number(process.env.PORT || 8181);
const ROOT_DIR = __dirname;

const MIME_TYPES = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".txt": "text/plain; charset=utf-8",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon",
  ".map": "application/json; charset=utf-8",
};

function getMimeType(filePath) {
  const ext = path.extname(filePath).toLowerCase();
  return MIME_TYPES[ext] || "application/octet-stream";
}

function sendNotFound(res) {
  res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
  res.end("404 Not Found");
}

function sendServerError(res) {
  res.writeHead(500, { "Content-Type": "text/plain; charset=utf-8" });
  res.end("500 Internal Server Error");
}

const server = http.createServer((req, res) => {
  const urlPath = decodeURIComponent((req.url || "/").split("?")[0]);

  // 根路径默认跳转到工具页。
  const rawPath = urlPath === "/" ? "/tool.html" : urlPath;
  const safePath = path.normalize(rawPath).replace(/^(\.\.[/\\])+/, "");
  const filePath = path.join(ROOT_DIR, safePath);

  // 只提供当前目录下的静态文件读取。
  if (!filePath.startsWith(ROOT_DIR)) {
    sendNotFound(res);
    return;
  }

  fs.stat(filePath, (statErr, stats) => {
    if (statErr) {
      if (statErr.code === "ENOENT") {
        sendNotFound(res);
        return;
      }
      sendServerError(res);
      return;
    }

    const targetPath = stats.isDirectory() ? path.join(filePath, "index.html") : filePath;

    fs.readFile(targetPath, (readErr, data) => {
      if (readErr) {
        if (readErr.code === "ENOENT") {
          sendNotFound(res);
          return;
        }
        sendServerError(res);
        return;
      }

      res.writeHead(200, { "Content-Type": getMimeType(targetPath) });
      res.end(data);
    });
  });
});

server.listen(PORT, HOST, () => {
  // 启动提示方便直接访问页面。
  console.log(`Web server running at http://localhost:${PORT}`);
});
