const { contextBridge, ipcRenderer } = require("electron");

function invoke(channel, ...args) {
  return ipcRenderer.invoke(channel, ...args);
}

contextBridge.exposeInMainWorld("sdlcWatch", {
  config: () => invoke("sdlc-watch:config"),
  setDbPath: (dbPath) => invoke("sdlc-watch:set-db-path", dbPath),
  reindex: () => invoke("sdlc-watch:reindex"),
  listRequirements: (limit) => invoke("sdlc-watch:list-requirements", limit),
  getRequirement: (requirement) => invoke("sdlc-watch:get-requirement", requirement),
  getDocument: (document) => invoke("sdlc-watch:get-document", document),
  search: (query, limit) => invoke("sdlc-watch:search", query, limit),
  onOpenIndexDialog: (callback) => {
    if (typeof callback !== "function") return () => {};
    const listener = () => callback();
    ipcRenderer.on("sdlc-watch:open-index-dialog", listener);
    return () => ipcRenderer.removeListener("sdlc-watch:open-index-dialog", listener);
  },
});
