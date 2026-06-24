import React, { startTransition, useCallback, useDeferredValue, useEffect, useMemo, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import Button from "@mui/material/Button";
import CssBaseline from "@mui/material/CssBaseline";
import Dialog from "@mui/material/Dialog";
import DialogActions from "@mui/material/DialogActions";
import DialogContent from "@mui/material/DialogContent";
import DialogTitle from "@mui/material/DialogTitle";
import IconButton from "@mui/material/IconButton";
import MenuItem from "@mui/material/MenuItem";
import Paper from "@mui/material/Paper";
import TextField from "@mui/material/TextField";
import Tooltip from "@mui/material/Tooltip";
import { createTheme, ThemeProvider } from "@mui/material/styles";
import ChevronLeftRoundedIcon from "@mui/icons-material/ChevronLeftRounded";
import CloseRoundedIcon from "@mui/icons-material/CloseRounded";
import DatasetRoundedIcon from "@mui/icons-material/DatasetRounded";
import MenuOpenRoundedIcon from "@mui/icons-material/MenuOpenRounded";
import RefreshRoundedIcon from "@mui/icons-material/RefreshRounded";
import SearchRoundedIcon from "@mui/icons-material/SearchRounded";
import { RichTreeView } from "@mui/x-tree-view/RichTreeView";
import { gsap } from "gsap";
import { useGSAP } from "@gsap/react";
import { headingAnchorId, MarkdownText, ProbeAnchorNav } from "./components/markdown";
import { parseMarkdownBlocks } from "./utils/markdown/parser";
import { markdownProfile, tableProfile } from "./utils/markdown/profile";
import { buildProbeBlocks, buildProbeGroups, endpointPath, probeTableRows, shortCellText } from "./utils/markdown/probe";
import "./styles.css";

gsap.registerPlugin(useGSAP);

const muiTheme = createTheme({
  palette: {
    mode: "light",
    primary: { main: "#14766f" },
    secondary: { main: "#b7791f" },
    background: {
      default: "#f5f8f8",
      paper: "#ffffff",
    },
    text: {
      primary: "#263238",
      secondary: "#637381",
    },
  },
  shape: {
    borderRadius: 8,
  },
  typography: {
    fontFamily: [
      "Aptos",
      "HarmonyOS Sans SC",
      "Source Han Sans SC",
      "Noto Sans CJK SC",
      "Microsoft YaHei",
      "sans-serif",
    ].join(","),
  },
  components: {
    MuiButton: {
      defaultProps: {
        disableElevation: true,
      },
      styleOverrides: {
        root: {
          textTransform: "none",
          fontWeight: 760,
        },
      },
    },
    MuiTextField: {
      defaultProps: {
        size: "small",
        variant: "outlined",
      },
    },
  },
});

const TREE_PANE_WIDTH_KEY = "sdlc-watch.treePaneWidth";
const TREE_PANE_DEFAULT_WIDTH = 336;
const TREE_PANE_MIN_WIDTH = 280;
const TREE_PANE_MAX_WIDTH = 560;
const DB_PATH_KEY = "sdlc-watch.dbPath";
const PROJECT_KEY = "sdlc-watch.selectedProject";
const TREE_COLLAPSED_KEY = "sdlc-watch.treeCollapsed";
const DESIGN_STATUS_OPTIONS = ["全部", "草稿", "评审中", "已发布", "已废弃"];

function clampTreePaneWidth(value) {
  const number = Number(value);
  if (!Number.isFinite(number)) return TREE_PANE_DEFAULT_WIDTH;
  return Math.min(TREE_PANE_MAX_WIDTH, Math.max(TREE_PANE_MIN_WIDTH, number));
}

function readTreePaneWidth() {
  try {
    return clampTreePaneWidth(window.localStorage.getItem(TREE_PANE_WIDTH_KEY));
  } catch (_error) {
    return TREE_PANE_DEFAULT_WIDTH;
  }
}

function readStoredDbPath() {
  try {
    return window.localStorage.getItem(DB_PATH_KEY) || "";
  } catch (_error) {
    return "";
  }
}

function readStoredProject() {
  try {
    return window.localStorage.getItem(PROJECT_KEY) || "";
  } catch (_error) {
    return "";
  }
}

function readStoredTreeCollapsed() {
  try {
    return window.localStorage.getItem(TREE_COLLAPSED_KEY) === "1";
  } catch (_error) {
    return false;
  }
}

const STAGE_LABELS = {
  "001": "概要设计",
  "002": "详细设计",
  "003": "施工记录",
  "004": "测试用例",
  "005": "测试报告",
  "006": "Debug 记录",
  status: "状态",
  summary: "摘要",
  "mini-plan": "轻量计划",
  operations: "执行日志",
  testing: "测试过程",
  verification: "验证记录",
  review: "自审报告",
  probe_result: "链路探针",
};
const UNIFIED_READER_DOCUMENT_TYPES = new Set(["001", "002", "003", "004", "005", "status", "operations", "testing", "verification", "review"]);

async function requestJson(path, options = {}) {
  const response = await fetch(path, {
    headers: {
      "content-type": "application/json",
      ...(options.headers || {}),
    },
    ...options,
  });
  const payload = await response.json().catch(() => ({
    ok: false,
    error: "invalid_response",
    message: "服务端返回内容不是 JSON。",
  }));
  return response.ok ? payload : { ok: false, status: response.status, ...payload };
}

const api = {
  config: () => requestJson("/api/config"),
  setDbPath: (dbPath) => requestJson("/api/db-path", {
    method: "POST",
    body: JSON.stringify({ dbPath }),
  }),
  reindex: () => requestJson("/api/reindex", { method: "POST" }),
  listRequirements: (limit) => requestJson(`/api/requirements?limit=${encodeURIComponent(limit || 200)}`),
  getRequirement: (requirement) => requestJson(`/api/requirements/${encodeURIComponent(requirement)}`),
  getDocument: (document) => requestJson(`/api/documents/${encodeURIComponent(document)}`),
  search: (query, limit) => requestJson(`/api/search?q=${encodeURIComponent(query)}&limit=${encodeURIComponent(limit || 50)}`),
};

function parseHash() {
  const params = new URLSearchParams(window.location.hash.slice(1));
  const status = params.get("status") || "全部";
  return {
    project: params.get("project") || "",
    requirement: params.get("requirement") || "",
    document: params.get("document") || "",
    query: params.get("q") || "",
    status: DESIGN_STATUS_OPTIONS.includes(status) ? status : statusChipLabel(status),
  };
}

function writeHash(state) {
  const params = new URLSearchParams();
  if (state.project) params.set("project", state.project);
  if (state.requirement) params.set("requirement", state.requirement);
  if (state.document) params.set("document", state.document);
  if (state.query) params.set("q", state.query);
  if (state.status && state.status !== "全部") params.set("status", state.status);
  const next = params.toString();
  window.history.replaceState(null, "", next ? `#${next}` : window.location.pathname);
}

function displayDate(value) {
  if (!value) return "-";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat(navigator.languages, {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(date);
}

function documentSortTime(document) {
  return String(document?.probe_request_time || document?.updated_at || "");
}

function displayDocumentTime(document) {
  return displayDate(documentSortTime(document));
}

function bytes(value) {
  const size = Number(value) || 0;
  return new Intl.NumberFormat(navigator.languages).format(size);
}

function stageLabel(type) {
  return STAGE_LABELS[type] || type || "文档";
}

function normalizeStatus(value) {
  const text = (value || "").trim();
  return text || "未标记";
}

function statusChipLabel(value) {
  const text = normalizeStatus(value);
  if (text === "全部") return text;
  if (/完成|发布|通过|就绪/.test(text)) return "已发布";
  if (/废弃|取消|归档/.test(text)) return "已废弃";
  if (/评审|审核|确认/.test(text)) return "评审中";
  if (/未标记|草稿|待/.test(text)) return "草稿";
  return text.length > 5 ? `${text.slice(0, 5)}…` : text;
}

function projectOf(item) {
  return item.project_name || String(item.slug || "").split("/")[0] || "未归类";
}

function shortRequirementName(item) {
  const project = projectOf(item);
  const slug = String(item.slug || "");
  return slug.startsWith(`${project}/`) ? slug.slice(project.length + 1) : slug;
}

function requirementTreeId(item) {
  return `requirement:${item.id}`;
}

function documentTreeId(item) {
  return `document:${item.id}`;
}

function execGroupTreeId(requirement, groupKey) {
  return `exec-group:${requirement.id}:${groupKey}`;
}

function searchTreeId(item) {
  return `search:${item.id}`;
}

function executionInfo(requirement, document) {
  const path = String(document.relative_path || "").replaceAll("\\", "/");
  const rootPath = String(requirement.root_path || "").replaceAll("\\", "/");
  const localPath = path.startsWith(`${rootPath}/`) ? path.slice(rootPath.length + 1) : path;
  const parts = localPath.split("/").filter(Boolean);
  if (parts.length < 3 || document.document_type !== "exec_result") return null;
  const folder = parts[0] || "执行脚本";
  const scriptName = folder.endsWith(".php") ? folder : `${folder}.php`;
  const date = parts[parts.length - 2] || "";
  const file = parts[parts.length - 1] || "";
  const displayFile = `${date}-${file}`;
  const time = file
    .replace(/\.md$/i, "")
    .replace(/^(\d{1,2})时(\d{1,2})分(\d{1,2})秒$/, (_match, hour, minute, second) => {
      return `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}:${String(second).padStart(2, "0")}`;
    });
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return null;
  return { folder, scriptName, date, file, displayFile, time, groupKey: scriptName };
}

function documentDisplayTitle(document, requirement) {
  if (!document) return "文档阅读";
  const execInfo = requirement ? executionInfo(requirement, document) : null;
  if (execInfo) return `${execInfo.scriptName} / ${execInfo.displayFile}`;
  return document.title || document.relative_path || "文档阅读";
}

function EmptyState({ title, detail }) {
  return (
    <Paper className="empty-state" elevation={0} role="status" aria-live="polite">
      <p className="empty-title">{title}</p>
      <p className="empty-detail">{detail}</p>
    </Paper>
  );
}

function SdlcTree({ items, selectedItem, expandedItems, onExpandedItemsChange, onItemClick }) {
  if (!items.length) {
    return <EmptyState title="暂无树节点" detail="刷新索引或调整搜索条件后再查看。" />;
  }
  return (
    <RichTreeView
      id="sdlc-tree"
      className="sdlc-tree"
      items={items}
      selectedItems={selectedItem || null}
      expandedItems={expandedItems}
      onExpandedItemsChange={onExpandedItemsChange}
      onItemClick={onItemClick}
      itemChildrenIndentation={18}
      aria-label="SDLC 项目需求文档树"
    />
  );
}

function DocumentAddressNav({ documents, selectedDocument, onOpenDocument }) {
  const documentCount = new Intl.NumberFormat(navigator.languages).format(documents.length);
  return (
    <Paper component="aside" elevation={0} className="address-nav" aria-labelledby="address-nav-heading">
      <div className="address-nav-heading">
        <div>
          <h2 id="address-nav-heading">地址导航</h2>
          <p>{documentCount} 份阶段文档</p>
        </div>
        <RefreshRoundedIcon fontSize="small" aria-hidden="true" />
      </div>
      <div className="address-search" aria-hidden="true">
        <SearchRoundedIcon fontSize="small" />
        <span>搜索文档地址...</span>
      </div>
      <div className="address-nav-list">
        {documents.map((document) => {
          const active = selectedDocument?.id === document.id;
          return (
            <button
              type="button"
              className={`address-nav-item ${active ? "is-active" : ""}`}
              key={document.id}
              onClick={() => onOpenDocument(document)}
            >
              <span className={`address-method address-method-${String(document.document_type || "doc").replace(/[^a-z0-9_-]/gi, "-").toLowerCase()}`}>
                {stageLabel(document.document_type).slice(0, 4)}
              </span>
              <span className="address-copy">
                <strong>{document.title || document.relative_path}</strong>
                <em translate="no">{document.relative_path}</em>
              </span>
            </button>
          );
        })}
      </div>
    </Paper>
  );
}

function HeadingAnchorNav({ headings }) {
  const [open, setOpen] = useState(false);

  const scrollToHeading = (event, id) => {
    event.preventDefault();
    const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    document.getElementById(id)?.scrollIntoView({ block: "start", behavior: reduceMotion ? "auto" : "smooth" });
  };

  if (!headings.length) return null;

  return (
    <Paper component="nav" className={`floating-anchor-nav heading-anchor-nav ${open ? "is-open" : ""}`} aria-label="文档标题导航" elevation={0}>
      <button
        type="button"
        className="floating-anchor-trigger"
        aria-expanded={open}
        onClick={() => setOpen((current) => !current)}
      >
        标题导航
      </button>
      <div className="floating-anchor-panel">
        <h4>标题导航</h4>
        {headings.map((heading) => (
          <a
            href={`#${heading.id}`}
            className={`heading-anchor-item heading-anchor-${heading.level}`}
            key={heading.id}
            onClick={(event) => scrollToHeading(event, heading.id)}
          >
            <span>{heading.text}</span>
          </a>
        ))}
      </div>
    </Paper>
  );
}

function App() {
  const rootRef = useRef(null);
  const topSearchRef = useRef(null);
  const hash = useMemo(() => parseHash(), []);
  const [config, setConfig] = useState(null);
  const [dbPathInput, setDbPathInput] = useState(readStoredDbPath);
  const [requirements, setRequirements] = useState([]);
  const [selectedProject, setSelectedProject] = useState(() => hash.project || readStoredProject());
  const [selectedRequirement, setSelectedRequirement] = useState(null);
  const [documents, setDocuments] = useState([]);
  const [documentMap, setDocumentMap] = useState(() => new Map());
  const [selectedDocument, setSelectedDocument] = useState(null);
  const [query, setQuery] = useState(hash.query);
  const [statusFilter, setStatusFilter] = useState(hash.status);
  const [searchResults, setSearchResults] = useState([]);
  const [expandedItems, setExpandedItems] = useState([]);
  const [treePaneWidth, setTreePaneWidth] = useState(readTreePaneWidth);
  const [isTreeCollapsed, setIsTreeCollapsed] = useState(readStoredTreeCollapsed);
  const [indexDialogOpen, setIndexDialogOpen] = useState(false);
  const [indexDialogMode, setIndexDialogMode] = useState("actions");
  const [isResizingTree, setIsResizingTree] = useState(false);
  const [probeViewMode, setProbeViewMode] = useState("v2");
  const [selectedProbePath, setSelectedProbePath] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("正在读取索引…");
  const deferredQuery = useDeferredValue(query);

  const projects = useMemo(() => {
    const groups = new Map();
    for (const item of requirements) {
      const project = projectOf(item);
      groups.set(project, (groups.get(project) || 0) + 1);
    }
    return Array.from(groups, ([name, count]) => ({ name, count })).sort((a, b) => a.name.localeCompare(b.name, "zh-CN"));
  }, [requirements]);

  const activeProject = projects.some((item) => item.name === selectedProject) ? selectedProject : "";

  useGSAP(
    () => {
      if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
      gsap.from(".workspace-pane", {
        opacity: 0,
        y: 12,
        duration: 0.28,
        stagger: 0.05,
        ease: "power2.out",
      });
    },
    { scope: rootRef },
  );

  useGSAP(
    () => {
      if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
      gsap.from(".markdown-view > *", {
        opacity: 0,
        y: 6,
        duration: 0.18,
        stagger: 0.01,
        ease: "power2.out",
      });
    },
    { scope: rootRef, dependencies: [selectedDocument?.id || 0], revertOnUpdate: true },
  );

  const openDocument = useCallback(async (item) => {
    setMessage(`正在打开 ${item.relative_path}…`);
    const result = await api.getDocument(String(item.id));
    if (!result.ok) {
      setMessage(result.message || "读取文档失败。");
      return;
    }
    setSelectedDocument(result.document);
    setMessage("文档已打开。");
  }, []);

  const openRequirement = useCallback(async (item, preferredDocument = "", options = {}) => {
    setSelectedProject(projectOf(item));
    setSelectedRequirement(item);
    setSelectedDocument(null);
    setDocuments([]);
    setMessage(`正在读取 ${shortRequirementName(item)}…`);
    const result = await api.getRequirement(String(item.id));
    if (!result.ok) {
      setMessage(result.message || "读取需求详情失败。");
      return;
    }
    const nextDocuments = result.documents || [];
    setDocumentMap((current) => {
      const next = new Map(current);
      next.set(String(item.id), nextDocuments);
      return next;
    });
    setDocuments(nextDocuments);
    setMessage(nextDocuments.length ? "需求文档已加载。" : "该需求暂未索引到文档。");
    const target = preferredDocument ? nextDocuments.find((doc) => String(doc.id) === String(preferredDocument)) : null;
    if (target) {
      const execInfo = executionInfo(item, target);
      const nextExpandedItems = [requirementTreeId(item)];
      if (execInfo) {
        nextExpandedItems.push(execGroupTreeId(item, execInfo.groupKey));
      }
      setExpandedItems(nextExpandedItems);
      await openDocument(target);
    } else if (preferredDocument || options.expand) {
      setExpandedItems([requirementTreeId(item)]);
    }
  }, [openDocument]);

  const preloadProjectDocuments = useCallback(async (project, sourceRequirements) => {
    const targets = sourceRequirements.filter((item) => projectOf(item) === project);
    if (!targets.length) return;
    const loaded = await Promise.all(
      targets.map(async (item) => {
        const result = await api.getRequirement(String(item.id));
        return [String(item.id), result.ok ? result.documents || [] : []];
      }),
    );
    setDocumentMap((current) => {
      const next = new Map(current);
      for (const [id, nextDocuments] of loaded) next.set(id, nextDocuments);
      return next;
    });
  }, []);

  const loadRequirements = useCallback(async (preferredSlug = "") => {
    setBusy(true);
    setMessage("正在读取需求列表…");
    const configResult = await api.config();
    let activeConfig = configResult;
    const storedDbPath = readStoredDbPath();
    if (configResult.ok && storedDbPath && storedDbPath !== configResult.dbPath) {
      activeConfig = await api.setDbPath(storedDbPath);
    }
    if (activeConfig.ok) {
      setConfig(activeConfig);
      setDbPathInput(activeConfig.dbPath || "");
    }
    const listResult = await api.listRequirements(500);
    if (!listResult.ok) {
      setMessage(listResult.message || "读取需求列表失败。请先刷新索引。");
      setRequirements([]);
      setBusy(false);
      return;
    }
    const nextRequirements = listResult.requirements || [];
    startTransition(() => {
      setRequirements(nextRequirements);
      setMessage(nextRequirements.length ? "索引已就绪。" : "索引为空，请刷新索引。");
    });
    const storedProject = readStoredProject();
    const requestedProject = hash.project || storedProject || selectedProject;
    const nextProject = nextRequirements.some((item) => projectOf(item) === requestedProject)
      ? requestedProject
      : projectOf(nextRequirements[0] || {});
    if (nextProject) {
      setSelectedProject(nextProject);
      try {
        window.localStorage.setItem(PROJECT_KEY, nextProject);
      } catch (_error) {
        // localStorage 不可用时仅保留当前会话项目选择。
      }
      await preloadProjectDocuments(nextProject, nextRequirements);
    }
    const target = nextRequirements.find((item) => item.slug === (preferredSlug || hash.requirement));
    if (target) await openRequirement(target, hash.document);
    setBusy(false);
  }, [hash.document, hash.project, hash.requirement, openRequirement, preloadProjectDocuments, selectedProject]);

  useEffect(() => {
    loadRequirements(hash.requirement);
  }, [loadRequirements, hash.requirement]);

  useEffect(() => {
    try {
      window.localStorage.setItem(TREE_PANE_WIDTH_KEY, String(Math.round(treePaneWidth)));
    } catch (_error) {
      // localStorage 不可用时仅保留当前会话宽度。
    }
  }, [treePaneWidth]);

  useEffect(() => {
    try {
      window.localStorage.setItem(TREE_COLLAPSED_KEY, isTreeCollapsed ? "1" : "0");
    } catch (_error) {
      // localStorage 不可用时仅保留当前会话折叠状态。
    }
  }, [isTreeCollapsed]);

  useEffect(() => {
    if (!activeProject) return;
    try {
      window.localStorage.setItem(PROJECT_KEY, activeProject);
    } catch (_error) {
      // localStorage 不可用时仅保留当前会话项目选择。
    }
  }, [activeProject]);

  useEffect(() => {
    writeHash({
      project: activeProject,
      requirement: selectedRequirement?.slug || "",
      document: selectedDocument?.id ? String(selectedDocument.id) : "",
      query,
      status: statusFilter,
    });
  }, [activeProject, selectedRequirement, selectedDocument, query, statusFilter]);

  useEffect(() => {
    let cancelled = false;
    const run = async () => {
      const text = deferredQuery.trim();
      if (!text) {
        setSearchResults([]);
        return;
      }
      const result = await api.search(text, 24);
      if (!cancelled) setSearchResults(result.ok ? result.results || [] : []);
    };
    run();
    return () => {
      cancelled = true;
    };
  }, [deferredQuery]);

  const statusOptions = DESIGN_STATUS_OPTIONS;
  const statusPillOptions = DESIGN_STATUS_OPTIONS;

  const filteredRequirements = useMemo(() => {
    const text = deferredQuery.trim().toLowerCase();
    return requirements.filter((item) => {
      const normalizedStatus = statusChipLabel(item.status);
      const matchesStatus = statusFilter === "全部" || normalizedStatus === statusFilter;
      const haystack = `${item.slug} ${item.title} ${item.summary} ${item.root_path} ${projectOf(item)}`.toLowerCase();
      return matchesStatus && (!text || haystack.includes(text));
    });
  }, [requirements, deferredQuery, statusFilter]);

  const groupedDocuments = useMemo(() => {
    return [...documents].sort((a, b) => {
      const stage = String(a.document_type).localeCompare(String(b.document_type));
      if (stage) return stage;
      const time = documentSortTime(b).localeCompare(documentSortTime(a));
      return time || String(a.relative_path).localeCompare(String(b.relative_path));
    });
  }, [documents]);

  const { treeItems, treeNodeMap } = useMemo(() => {
    const nodes = new Map();
    const projectRequirements = filteredRequirements
      .filter((item) => projectOf(item) === activeProject)
      .sort((a, b) => String(a.title || a.slug).localeCompare(String(b.title || b.slug), "zh-CN"));
    const requirementNodes = projectRequirements.map((requirement) => {
      const requirementId = requirementTreeId(requirement);
      nodes.set(requirementId, { type: "requirement", requirement });
      const docs = [...(documentMap.get(String(requirement.id)) || [])].sort((a, b) => {
        const stage = String(a.document_type).localeCompare(String(b.document_type));
        if (stage) return stage;
        const time = documentSortTime(b).localeCompare(documentSortTime(a));
        return time || String(a.relative_path).localeCompare(String(b.relative_path));
      });
      const normalDocs = [];
      const execGroups = new Map();
      for (const document of docs) {
        const execInfo = executionInfo(requirement, document);
        if (!execInfo) {
          normalDocs.push(document);
          continue;
        }
        if (!execGroups.has(execInfo.groupKey)) {
          execGroups.set(execInfo.groupKey, { info: execInfo, documents: [] });
        }
        execGroups.get(execInfo.groupKey).documents.push({ document, execInfo });
      }
      const normalChildren = normalDocs.map((document) => {
        const documentId = documentTreeId(document);
        nodes.set(documentId, { type: "document", requirement, document });
        return {
          id: documentId,
          label: `${stageLabel(document.document_type)} · ${document.title || document.relative_path}`,
        };
      });
      const execChildren = Array.from(execGroups.values())
        .sort((a, b) => a.info.groupKey.localeCompare(b.info.groupKey, "zh-CN"))
        .map((group) => {
          const groupId = execGroupTreeId(requirement, group.info.groupKey);
          nodes.set(groupId, { type: "exec-group", requirement });
          const children = group.documents
            .sort((a, b) => String(b.execInfo.displayFile).localeCompare(String(a.execInfo.displayFile), "zh-CN"))
            .map(({ document, execInfo }) => {
              const documentId = documentTreeId(document);
              nodes.set(documentId, { type: "document", requirement, document });
              return {
                id: documentId,
                label: execInfo.displayFile,
              };
            });
          return {
            id: groupId,
            label: `${group.info.scriptName} · ${new Intl.NumberFormat(navigator.languages).format(children.length)} 次`,
            children,
          };
        });
      return {
        id: requirementId,
        label: `${requirement.title || shortRequirementName(requirement)} · ${new Intl.NumberFormat(navigator.languages).format(requirement.document_count || docs.length || 0)} 份`,
        children: [...normalChildren, ...execChildren],
      };
    });

    if (deferredQuery.trim() && searchResults.length) {
      const searchChildren = searchResults
        .filter((item) => !activeProject || (item.project_name || "") === activeProject)
        .map((item) => {
          const id = searchTreeId(item);
          nodes.set(id, { type: "search", result: item });
          return {
            id,
            label: `${item.title || item.relative_path}`,
          };
        });
      nodes.set("search:root", { type: "search-root" });
      if (searchChildren.length) {
        requirementNodes.unshift({
          id: "search:root",
          label: `全文命中 · ${new Intl.NumberFormat(navigator.languages).format(searchChildren.length)} 项`,
          children: searchChildren,
        });
      }
    }

    return { treeItems: requirementNodes, treeNodeMap: nodes };
  }, [activeProject, deferredQuery, documentMap, filteredRequirements, searchResults]);

  const selectedTreeItem = selectedDocument?.id
    ? documentTreeId(selectedDocument)
    : selectedRequirement?.id
      ? requirementTreeId(selectedRequirement)
      : "";
  const selectedReaderMode = selectedDocument?.content
    ? markdownProfile(selectedDocument.content, selectedDocument.document_type)
        .split(" ")
        .filter(Boolean)
        .map((name) => `reader-${name}`)
        .join(" ")
    : "";
  const selectedReaderDocumentType = `reader-doc-${String(selectedDocument?.document_type || "empty").replace(/[^a-z0-9_-]/gi, "-").toLowerCase()}`;
  const omitFirstMarkdownHeading = selectedDocument ? UNIFIED_READER_DOCUMENT_TYPES.has(selectedDocument.document_type) : false;
  const probeAnchorBlocks = useMemo(() => {
    if (!selectedReaderMode.includes("probe-report") || !selectedDocument?.content) return [];
    return parseMarkdownBlocks(selectedDocument.content).flatMap((block, index) => {
      if (block.type !== "table" || tableProfile(block.rows) !== "probe-table") return [];
      const { header, rows } = probeTableRows(block.rows);
      return buildProbeBlocks(header, rows, `${block.type}-${index}`);
    });
  }, [selectedDocument?.content, selectedReaderMode]);
  const probeGroups = useMemo(() => buildProbeGroups(probeAnchorBlocks), [probeAnchorBlocks]);
  useEffect(() => {
    if (!probeGroups.length) {
      setSelectedProbePath("");
      return;
    }
    if (!probeGroups.some((group) => group.key === selectedProbePath)) {
      setSelectedProbePath(probeGroups[0].key);
    }
  }, [probeGroups, selectedProbePath]);
  const selectedProbeGroup = probeGroups.find((group) => group.key === selectedProbePath) || probeGroups[0] || null;
  const documentHeadingAnchors = useMemo(() => {
    if (probeAnchorBlocks.length || !selectedDocument?.content) return [];
    const blocks = parseMarkdownBlocks(selectedDocument.content);
    const firstContentBlockIndex = blocks.findIndex((block) => block.type !== "space");
    return blocks.flatMap((block, index) => {
      if (omitFirstMarkdownHeading && index === firstContentBlockIndex && block.type === "h1") return [];
      if (!["h1", "h2", "h3"].includes(block.type)) return [];
      const text = String(block.text || "").trim();
      if (!text) return [];
      return [{ id: headingAnchorId(index), level: block.type, text }];
    });
  }, [omitFirstMarkdownHeading, probeAnchorBlocks.length, selectedDocument?.content]);
  const readerDisplayTitle = probeViewMode === "v2" && selectedProbeGroup
    ? `${selectedProbeGroup.path}（${selectedProbeGroup.blocks.length} 次请求）`
    : probeAnchorBlocks.length
    ? `${endpointPath(probeAnchorBlocks[0].endpoint)}（${shortCellText(probeAnchorBlocks[0].result, "成功").replace(/^通过[:：]?\s*/, "")}）`
    : documentDisplayTitle(selectedDocument, selectedRequirement);
  const isProbeDocument = probeAnchorBlocks.length > 0;

  const applyDbPath = async () => {
    const nextDbPath = dbPathInput.trim();
    setBusy(true);
    setMessage("正在切换 SQLite 索引库…");
    const result = await api.setDbPath(nextDbPath);
    if (!result.ok) {
      setMessage(result.message || "切换索引库失败。");
      setBusy(false);
      return false;
    }
    try {
      window.localStorage.setItem(DB_PATH_KEY, result.dbPath || nextDbPath);
    } catch (_error) {
      // localStorage 不可用时仅在本次浏览器会话内生效。
    }
    setConfig(result);
    setDbPathInput(result.dbPath || nextDbPath);
    setDocumentMap(new Map());
    setRequirements([]);
    setSelectedProject("");
    setSelectedRequirement(null);
    setSelectedDocument(null);
    setDocuments([]);
    setExpandedItems([]);
    await loadRequirements("");
    setMessage(`已切换索引库：${result.dbPath || nextDbPath}`);
    setBusy(false);
    return true;
  };

  const refreshIndex = async () => {
    setBusy(true);
    setMessage("正在刷新 SQLite 索引…");
    const result = await api.reindex();
    if (!result.ok) {
      setMessage(result.message || "刷新索引失败。");
      setBusy(false);
      return false;
    }
    setDocumentMap(new Map());
    setMessage(`刷新完成：${result.scanned_requirements} 个需求，${result.scanned_documents} 份文档。`);
    await loadRequirements(selectedRequirement?.slug || hash.requirement);
    setBusy(false);
    return true;
  };

  const selectProject = async (project) => {
    setSelectedProject(project);
    try {
      window.localStorage.setItem(PROJECT_KEY, project);
    } catch (_error) {
      // localStorage 不可用时仅保留当前会话项目选择。
    }
    // 切换项目时必须清空旧需求和旧文档，否则受控 Tree 仍会选中上一个项目的文档。
    setSelectedRequirement(null);
    setSelectedDocument(null);
    setDocuments([]);
    await preloadProjectDocuments(project, requirements);
    setExpandedItems([]);
    setMessage(`已切换到 ${project}，请选择需求或文档。`);
  };

  const openIndexDialog = useCallback(() => {
    setIndexDialogMode("actions");
    setDbPathInput(config?.dbPath || readStoredDbPath());
    setIndexDialogOpen(true);
  }, [config?.dbPath]);

  useEffect(() => {
    const handleIndexShortcut = (event) => {
      if (!(event.ctrlKey || event.metaKey) || !event.shiftKey || event.key.toLowerCase() !== "u") return;
      event.preventDefault();
      openIndexDialog();
    };
    window.addEventListener("keydown", handleIndexShortcut);
    return () => window.removeEventListener("keydown", handleIndexShortcut);
  }, [openIndexDialog]);

  useEffect(() => {
    const handleSearchShortcut = (event) => {
      if (!(event.ctrlKey || event.metaKey) || event.key.toLowerCase() !== "k") return;
      event.preventDefault();
      topSearchRef.current?.focus();
    };
    window.addEventListener("keydown", handleSearchShortcut);
    return () => window.removeEventListener("keydown", handleSearchShortcut);
  }, []);

  const refreshIndexFromDialog = async () => {
    const ok = await refreshIndex();
    if (ok) setIndexDialogOpen(false);
  };

  const applyDbPathFromDialog = async () => {
    const ok = await applyDbPath();
    if (ok) setIndexDialogOpen(false);
  };

  const toggleTreeCollapsed = () => {
    setIsTreeCollapsed((current) => !current);
  };

  const handleExpandedItemsChange = async (_event, itemIds) => {
    const openedItem = itemIds.find((itemId) => !expandedItems.includes(itemId));
    if (!openedItem) {
      setExpandedItems(itemIds);
      return;
    }
    const node = treeNodeMap.get(openedItem);
    if (node?.type === "exec-group" && node.requirement) {
      setExpandedItems([requirementTreeId(node.requirement), openedItem]);
      return;
    }
    setExpandedItems([openedItem]);
  };

  const openSearchResult = async (item) => {
    const requirement = requirements.find((entry) => Number(entry.id) === Number(item.requirement_id));
    if (requirement) {
      await openRequirement(requirement, String(item.id));
      return;
    }
    await openDocument(item);
  };

  const handleTreeItemClick = async (_event, itemId) => {
    const node = treeNodeMap.get(itemId);
    if (!node) return;
    if (node.type === "requirement") {
      await openRequirement(node.requirement);
      return;
    }
    if (node.type === "document") {
      if (!selectedRequirement || Number(selectedRequirement.id) !== Number(node.requirement.id)) {
        await openRequirement(node.requirement, String(node.document.id));
        return;
      }
      await openDocument(node.document);
      return;
    }
    if (node.type === "search") await openSearchResult(node.result);
  };

  const startResizeTreePane = useCallback((event) => {
    event.preventDefault();
    const startX = event.clientX;
    const startWidth = treePaneWidth;
    setIsResizingTree(true);

    const handleMove = (moveEvent) => {
      setTreePaneWidth(clampTreePaneWidth(startWidth + moveEvent.clientX - startX));
    };

    const stopResize = () => {
      setIsResizingTree(false);
      window.removeEventListener("pointermove", handleMove);
      window.removeEventListener("pointerup", stopResize);
      window.removeEventListener("pointercancel", stopResize);
    };

    window.addEventListener("pointermove", handleMove);
    window.addEventListener("pointerup", stopResize, { once: true });
    window.addEventListener("pointercancel", stopResize, { once: true });
  }, [treePaneWidth]);

  const handleResizeKeyDown = useCallback((event) => {
    if (!["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) return;
    event.preventDefault();
    const step = event.shiftKey ? 40 : 16;
    setTreePaneWidth((current) => {
      if (event.key === "Home") return TREE_PANE_MIN_WIDTH;
      if (event.key === "End") return TREE_PANE_MAX_WIDTH;
      return clampTreePaneWidth(current + (event.key === "ArrowRight" ? step : -step));
    });
  }, []);

  return (
    <div className={`app-shell document-layout ${isProbeDocument ? "is-probe-document" : ""} ${isProbeDocument && probeViewMode === "v2" ? "is-probe-v2" : ""} ${isResizingTree ? "is-resizing-tree" : ""}`} ref={rootRef}>
      <a className="skip-link" href="#main-content">跳到正文</a>
      <header className="top-shell-bar">
        <div className="top-brand">
          <div className="product-mark" aria-hidden="true">D</div>
          <strong>DocView 文档查看器</strong>
        </div>
        <label className="top-project-switcher" aria-label="项目切换">
          <select value={activeProject} onChange={(event) => selectProject(event.target.value)} aria-label="项目切换">
            {projects.map((item) => (
              <option key={item.name} value={item.name}>
                {item.name}
              </option>
            ))}
          </select>
        </label>
        <div className="top-breadcrumb" aria-label="当前位置">
          {selectedRequirement && <span>{shortRequirementName(selectedRequirement)}</span>}
          <span>{selectedDocument?.relative_path || selectedRequirement?.root_path || "请选择文档"}</span>
        </div>
        <label className="top-search" htmlFor="top-global-search">
          <SearchRoundedIcon fontSize="small" />
          <input
            id="top-global-search"
            ref={topSearchRef}
            type="search"
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="搜索文档、接口、脚本文件..."
            autoComplete="off"
          />
          <kbd>⌘K</kbd>
        </label>
        <Button
          type="button"
          className="top-index-button"
          variant="outlined"
          startIcon={<DatasetRoundedIcon />}
          onClick={openIndexDialog}
          disabled={busy}
        >
          索引维护
        </Button>
        <div className="top-user">
          <span>张</span>
          <strong>张三</strong>
        </div>
      </header>
      <main
        id="main-content"
        className={`workspace-grid ${isTreeCollapsed ? "is-tree-collapsed" : ""} ${probeAnchorBlocks.length ? "has-probe-nav" : "no-right-nav"}`}
        tabIndex={-1}
        style={{
          "--tree-pane-width": `${isTreeCollapsed ? 52 : treePaneWidth}px`,
          "--tree-resizer-width": isTreeCollapsed ? "0rem" : "0.42rem",
        }}
      >
        <Paper
          component="section"
          elevation={0}
          className={`workspace-pane tree-pane tree-pane-doc ${isTreeCollapsed ? "is-collapsed" : ""}`}
          aria-labelledby="tree-heading"
        >
          <div className="tree-collapse-rail">
            <Tooltip title={isTreeCollapsed ? "展开菜单" : "折叠菜单"} placement="right">
              <IconButton
                type="button"
                className="tree-collapse-button"
                aria-label={isTreeCollapsed ? "展开左侧菜单" : "折叠左侧菜单"}
                onClick={toggleTreeCollapsed}
                size="small"
              >
                {isTreeCollapsed ? <MenuOpenRoundedIcon fontSize="small" /> : <ChevronLeftRoundedIcon fontSize="small" />}
              </IconButton>
            </Tooltip>
          </div>

          {!isTreeCollapsed && (
            <>
              <div className="pane-heading">
                <div>
                  <h2 id="tree-heading">文档目录</h2>
                  <p>{new Intl.NumberFormat(navigator.languages).format(projects.length)} 个启动目录 · {new Intl.NumberFormat(navigator.languages).format(filteredRequirements.length)} 个需求</p>
                </div>
              </div>
              <div className="tree-toolbar">
            <TextField
              id="project-switcher"
              name="project-switcher"
              className="text-input project-switcher"
              select
              label="项目"
              value={activeProject}
              onChange={(event) => selectProject(event.target.value)}
              fullWidth
            >
              {projects.map((item) => (
                <MenuItem key={item.name} value={item.name}>
                  {item.name} · {new Intl.NumberFormat(navigator.languages).format(item.count)} 个需求
                </MenuItem>
              ))}
            </TextField>
            <TextField
              id="sdlc-search"
              name="sdlc-search"
              className="text-input tree-search-input"
              type="search"
              label="搜索"
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder="输入需求、文档或关键词…"
              autoComplete="off"
              fullWidth
            />
            <TextField
              id="status-filter"
              name="status-filter"
              className="text-input status-filter-input"
              select
              label="状态"
              value={statusFilter}
              onChange={(event) => setStatusFilter(event.target.value)}
              fullWidth
            >
              {statusOptions.map((item) => (
                <MenuItem key={item} value={item}>{item}</MenuItem>
              ))}
            </TextField>
            <div className="tree-status-pills" aria-label="状态筛选">
              {statusPillOptions.map((item) => (
                <button
                  type="button"
                  key={item}
                  className={`tree-status-pill ${statusFilter === item ? "is-active" : ""}`}
                  onClick={() => setStatusFilter(item)}
                >
                  {statusChipLabel(item)}
                </button>
              ))}
            </div>
              </div>
              <div className="tree-scroll">
                <SdlcTree
                  items={treeItems}
                  selectedItem={selectedTreeItem}
                  expandedItems={expandedItems}
                  onExpandedItemsChange={handleExpandedItemsChange}
                  onItemClick={handleTreeItemClick}
                />
              </div>
            </>
          )}
        </Paper>

        <button
          type="button"
          className="pane-resizer"
          aria-label="拖拽调整左侧项目文档树宽度"
          title="拖拽调整左侧宽度"
          disabled={isTreeCollapsed}
          onPointerDown={startResizeTreePane}
          onKeyDown={handleResizeKeyDown}
        />

        <Paper component="section" elevation={0} className={`workspace-pane reader-pane reader-pane-wide ${selectedReaderDocumentType} ${selectedReaderMode}`} aria-labelledby="reader-heading">
          <div className="pane-heading reader-heading">
            <div className="min-w-0">
              <h2 id="reader-heading">
                <span>{readerDisplayTitle}</span>
                {selectedDocument && <em className="doc-status-pill">已发布</em>}
              </h2>
              <p translate="no">路径：{selectedDocument?.relative_path || selectedRequirement?.root_path || message}</p>
            </div>
            {isProbeDocument && (
              <div className="probe-style-switch">
                <span>样式模式</span>
                <Button
                  className="probe-style-toggle"
                  variant={probeViewMode === "v2" ? "contained" : "outlined"}
                  size="small"
                  aria-pressed={probeViewMode === "v2"}
                onClick={() => setProbeViewMode((current) => (current === "v2" ? "v1" : "v2"))}
              >
                  {probeViewMode === "v2" ? "V2 样式" : "V1 样式"}
              </Button>
              </div>
            )}
          </div>
          <dl className="reader-summary-strip">
            <div>
              <dt>文档编号</dt>
              <dd translate="no">{selectedDocument?.id ? `DOC_${String(selectedDocument.id).padStart(3, "0")}` : "-"}</dd>
            </div>
            <div>
              <dt>版本</dt>
              <dd translate="no">v1.0.0</dd>
            </div>
            <div>
              <dt>创建人</dt>
              <dd>Codex</dd>
            </div>
            <div className="reader-status-summary">
              <dt>更新时间</dt>
              <dd>{selectedDocument ? displayDocumentTime(selectedDocument) : "-"}</dd>
            </div>
          </dl>
          {selectedDocument && (
            <dl className="metadata-grid">
              <div><dt>项目</dt><dd translate="no">{activeProject}</dd></div>
              <div><dt>类型</dt><dd>{stageLabel(selectedDocument.document_type)}</dd></div>
              <div><dt>大小</dt><dd>{bytes(selectedDocument.size_bytes)} bytes</dd></div>
              <div><dt>更新</dt><dd>{displayDocumentTime(selectedDocument)}</dd></div>
            </dl>
          )}
          <MarkdownText
            content={selectedDocument?.content || ""}
            documentType={selectedDocument?.document_type || ""}
            omitFirstHeading={omitFirstMarkdownHeading}
            probeViewMode={probeViewMode}
            selectedProbePath={selectedProbePath}
          />
        </Paper>

        {probeAnchorBlocks.length
          ? (
              <ProbeAnchorNav
                blocks={probeAnchorBlocks}
                probeViewMode={probeViewMode}
                selectedProbePath={selectedProbePath}
                onSelectProbePath={setSelectedProbePath}
              />
            )
          : <HeadingAnchorNav headings={documentHeadingAnchors} />}
      </main>

      <footer className="status-bar" role="status" aria-live="polite">
        <span>{message}</span>
        <span translate="no">{config?.projectRoot || ""}</span>
      </footer>

      <Dialog
        open={indexDialogOpen}
        onClose={() => setIndexDialogOpen(false)}
        maxWidth={false}
        fullWidth={false}
        slotProps={{ paper: { className: `index-dialog-paper index-dialog-${indexDialogMode}` } }}
      >
        <DialogTitle className="index-dialog-title">
          <div className="index-dialog-heading">
            <span>索引维护</span>
            <small>{indexDialogMode === "database" ? "切换 SQLite 文件后会重新加载项目树" : "刷新 docs 索引或切换 SQLite 数据源"}</small>
          </div>
          <IconButton aria-label="关闭索引维护弹窗" onClick={() => setIndexDialogOpen(false)} size="small">
            <CloseRoundedIcon fontSize="small" />
          </IconButton>
        </DialogTitle>
        <DialogContent className="index-dialog-content">
          {indexDialogMode === "actions" ? (
            <div className="index-action-grid">
              <button type="button" className="index-action-card" onClick={refreshIndexFromDialog} disabled={busy}>
                <RefreshRoundedIcon />
                <span>{busy ? "正在刷新…" : "刷新索引"}</span>
                <small>重新扫描当前 docs 目录并更新 SQLite 索引。</small>
              </button>
              <button type="button" className="index-action-card" onClick={() => setIndexDialogMode("database")} disabled={busy}>
                <DatasetRoundedIcon />
                <span>更新索引位置</span>
                <small>切换 SQLite 文件路径，应用后重新加载项目树。</small>
              </button>
            </div>
          ) : (
            <div className="index-db-form">
              <TextField
                id="dialog-db-path-input"
                name="dialog-db-path-input"
                className="text-input"
                label="SQLite 索引库位置"
                value={dbPathInput}
                onChange={(event) => setDbPathInput(event.target.value)}
                onKeyDown={(event) => {
                  if (event.key === "Enter") applyDbPathFromDialog();
                }}
                placeholder="输入 SQLite 文件路径…"
                autoComplete="off"
                fullWidth
              />
              <p translate="no">{config?.dbPath || "当前未读取到索引库路径"}</p>
            </div>
          )}
        </DialogContent>
        <DialogActions className="index-dialog-actions">
          {indexDialogMode === "database" && (
            <Button type="button" variant="text" onClick={() => setIndexDialogMode("actions")} disabled={busy}>
              返回
            </Button>
          )}
          <Button type="button" variant="outlined" onClick={() => setIndexDialogOpen(false)} disabled={busy}>
            关闭
          </Button>
          {indexDialogMode === "database" && (
            <Button type="button" variant="contained" onClick={applyDbPathFromDialog} disabled={busy}>
              {busy ? "应用中…" : "应用并刷新"}
            </Button>
          )}
        </DialogActions>
      </Dialog>
    </div>
  );
}

createRoot(document.getElementById("root")).render(
  <ThemeProvider theme={muiTheme}>
    <CssBaseline />
    <App />
  </ThemeProvider>,
);
