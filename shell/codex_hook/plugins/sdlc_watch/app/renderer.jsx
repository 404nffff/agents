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
import { RichTreeView } from "@mui/x-tree-view/RichTreeView";
import { gsap } from "gsap";
import { useGSAP } from "@gsap/react";
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
      "Inter",
      "ui-sans-serif",
      "system-ui",
      "-apple-system",
      "BlinkMacSystemFont",
      "Segoe UI",
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

function api() {
  return window.sdlcWatch;
}

function parseHash() {
  const params = new URLSearchParams(window.location.hash.slice(1));
  return {
    project: params.get("project") || "",
    requirement: params.get("requirement") || "",
    document: params.get("document") || "",
    query: params.get("q") || "",
    status: params.get("status") || "全部",
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

function splitTableRow(line) {
  return line.replace(/^\|/, "").replace(/\|$/, "").split("|").map((cell) => cell.trim());
}

function markdownProfile(content) {
  const text = content || "";
  const isWorkPhp = text.includes("# 执行结果") && text.includes("执行命令：`docker exec work php");
  const isProbe = text.includes("| 接口地址 | 入参 | 出参 |") || text.includes("probe_result") || text.includes("management_backend_cleanup_probe");
  return [
    isWorkPhp ? "work-php-report" : "",
    isProbe ? "probe-report" : "",
  ].filter(Boolean).join(" ");
}

function tableProfile(rows) {
  const headerText = (rows[0] || []).join(" ");
  if (headerText.includes("接口地址") && headerText.includes("测试结果") && headerText.includes("关联脚本文件")) {
    return "probe-table";
  }
  return "";
}

function cellLineClass(line) {
  const text = String(line);
  const isJson = /^\{|\}$|^\[|\]$/.test(text) || /":\s*/.test(text);
  const isRisk = /失败|Authentication failure|error|failed|超时|风险|warnings|migration_gap|未执行|未配置/i.test(text);
  if (/^(JSON|字段说明|数据来源|环境|边界条件)/.test(text)) return "cell-kicker";
  if (/dry-run|不调用真实发送|不真实发送|不写库/.test(text)) return "cell-guard";
  if (/^(通过|检查通过|测试通过)/.test(text) || /"passed":\s*true/.test(text)) return "cell-pass";
  if (isJson && isRisk) return "cell-json cell-json-risk";
  if (isJson) return "cell-json";
  if (isRisk) return "cell-risk";
  return "";
}

function renderInlineText(text, keyPrefix) {
  const parts = String(text).split(/(`[^`]+`)/g);
  return parts.map((part, index) => {
    if (part.startsWith("`") && part.endsWith("`")) {
      return <code className="inline-code" key={`${keyPrefix}-code-${index}`}>{part.slice(1, -1)}</code>;
    }
    return <React.Fragment key={`${keyPrefix}-text-${index}`}>{part}</React.Fragment>;
  });
}

function renderTableCell(cell, keyPrefix) {
  return String(cell).split(/<br\s*\/?>/i).map((line, index) => (
    <span className={`cell-line ${cellLineClass(line)}`} key={`${keyPrefix}-line-${index}`}>
      {renderInlineText(line, `${keyPrefix}-${index}`)}
    </span>
  ));
}

function normalizedProbeHeader(value) {
  return String(value || "").replace(/\s+/g, "");
}

function probeCell(row, header, names) {
  const targets = new Set(names.map(normalizedProbeHeader));
  const index = header.findIndex((item) => targets.has(normalizedProbeHeader(item)));
  return index >= 0 ? row[index] || "" : "";
}

function probeBlockId(blockKey, rowIndex) {
  return `probe-${blockKey}-${rowIndex}`.replace(/[^a-zA-Z0-9_-]/g, "-");
}

function shortProbeAnchor(value, index) {
  const text = String(value || "").split(/<br\s*\/?>/i)[0].replace(/`/g, "").trim();
  return text || `接口 ${index + 1}`;
}

function shortProbeTime(value) {
  return String(value || "")
    .replace(/<br\s*\/?>/gi, " ")
    .replace(/`/g, "")
    .trim();
}

function probeTimeRank(value) {
  const text = shortProbeTime(value);
  const match = text.match(/(\d{4})-(\d{2})-(\d{2})(?:[\sT-]+(\d{1,2})(?:时|:)(\d{1,2})(?:分|:)?(\d{1,2})?)?/);
  if (!match) return 0;
  const [, year, month, day, hour = "0", minute = "0", second = "0"] = match;
  const time = new Date(
    Number(year),
    Number(month) - 1,
    Number(day),
    Number(hour),
    Number(minute),
    Number(second),
  ).getTime();
  return Number.isNaN(time) ? 0 : time;
}

function ProbeReportBlocks({ header, rows, blockKey }) {
  const blocks = rows
    .map((row, rowIndex) => {
      const requestTime = probeCell(row, header, ["请求时间"]);
      return {
        id: probeBlockId(blockKey, rowIndex),
        rowIndex,
        row,
        endpoint: probeCell(row, header, ["接口地址"]),
        input: probeCell(row, header, ["入参"]),
        output: probeCell(row, header, ["出参"]),
        condition: probeCell(row, header, ["测试条件"]),
        boundary: probeCell(row, header, ["边界条件"]),
        result: probeCell(row, header, ["测试结果"]),
        requestTime,
        requestTimeRank: probeTimeRank(requestTime),
        script: probeCell(row, header, ["关联脚本文件"]),
      };
    })
    .sort((left, right) => right.requestTimeRank - left.requestTimeRank || left.rowIndex - right.rowIndex);

  const scrollToProbeBlock = (event, id) => {
    event.preventDefault();
    document.getElementById(id)?.scrollIntoView({ block: "start", behavior: "smooth" });
  };

  return (
    <section className="probe-block-layout" aria-label="链路探针结果">
      <div className="probe-block-list">
        {blocks.map((block, index) => (
          <article className="probe-case-card" id={block.id} key={block.id}>
            <header className="probe-case-header">
              <div className="probe-case-title">
                <span>接口 {index + 1}</span>
                <h4>{renderTableCell(block.endpoint, `${block.id}-endpoint`)}</h4>
              </div>
              <div className="probe-case-meta">
                <div>{renderTableCell(block.result, `${block.id}-result`)}</div>
                {block.requestTime && <time>{renderTableCell(block.requestTime, `${block.id}-time`)}</time>}
              </div>
            </header>
            <div className="probe-case-grid">
              <section className="probe-field probe-field-wide probe-field-io probe-field-input">
                <h5>入参</h5>
                <div>{renderTableCell(block.input, `${block.id}-input`)}</div>
              </section>
              <section className="probe-field probe-field-wide probe-field-io probe-field-output">
                <h5>出参</h5>
                <div>{renderTableCell(block.output, `${block.id}-output`)}</div>
              </section>
              <section className="probe-field">
                <h5>测试条件</h5>
                <div>{renderTableCell(block.condition, `${block.id}-condition`)}</div>
              </section>
              <section className="probe-field">
                <h5>边界条件</h5>
                <div>{renderTableCell(block.boundary, `${block.id}-boundary`)}</div>
              </section>
              <section className="probe-field">
                <h5>关联脚本文件</h5>
                <div>{renderTableCell(block.script, `${block.id}-script`)}</div>
              </section>
            </div>
          </article>
        ))}
      </div>
      <nav className="probe-anchor-nav" aria-label="链路探针接口定位">
        <h4>接口定位</h4>
        {blocks.map((block, index) => (
          <a href={`#${block.id}`} key={`${block.id}-anchor`} onClick={(event) => scrollToProbeBlock(event, block.id)}>
            <span>{String(index + 1).padStart(2, "0")}</span>
            <span className="probe-anchor-copy">
              <strong>{shortProbeAnchor(block.endpoint, index)}</strong>
              {block.requestTime && <em>{shortProbeTime(block.requestTime)}</em>}
            </span>
          </a>
        ))}
      </nav>
    </section>
  );
}

function parseMarkdownBlocks(content) {
  const lines = (content || "").split(/\r?\n/);
  const blocks = [];
  let index = 0;
  while (index < lines.length) {
    const line = lines[index];
    if (line.startsWith("```")) {
      const language = line.slice(3).trim();
      const code = [];
      index += 1;
      while (index < lines.length && !lines[index].startsWith("```")) {
        code.push(lines[index]);
        index += 1;
      }
      blocks.push({ type: "code", language, code: code.join("\n") });
      index += 1;
      continue;
    }
    if (/^\|.+\|$/.test(line)) {
      const rows = [];
      while (index < lines.length && /^\|.+\|$/.test(lines[index])) {
        rows.push(splitTableRow(lines[index]));
        index += 1;
      }
      blocks.push({ type: "table", rows });
      continue;
    }
    if (/^\s*[-*]\s+/.test(line)) {
      const items = [];
      while (index < lines.length && /^\s*[-*]\s+/.test(lines[index])) {
        items.push(lines[index].replace(/^\s*[-*]\s+/, "").trim());
        index += 1;
      }
      blocks.push({ type: "list", items });
      continue;
    }
    if (line.startsWith("### ")) blocks.push({ type: "h3", text: line.slice(4) });
    else if (line.startsWith("## ")) blocks.push({ type: "h2", text: line.slice(3) });
    else if (line.startsWith("# ")) blocks.push({ type: "h1", text: line.slice(2) });
    else if (line.startsWith("> ")) blocks.push({ type: "quote", text: line.slice(2) });
    else if (/^---+$/.test(line.trim())) blocks.push({ type: "hr" });
    else if (line.trim()) blocks.push({ type: "paragraph", text: line });
    else blocks.push({ type: "space" });
    index += 1;
  }
  return blocks;
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

function MarkdownText({ content }) {
  const blocks = useMemo(() => parseMarkdownBlocks(content), [content]);
  const profileClass = useMemo(() => markdownProfile(content), [content]);
  if (!content) {
    return <EmptyState title="未选择文档" detail="选择阶段文档后会在这里显示全文。" />;
  }
  return (
    <article className={`markdown-view ${profileClass}`}>
      {blocks.map((block, index) => {
        const key = `${block.type}-${index}`;
        if (block.type === "h1") return <h1 key={key}>{block.text}</h1>;
        if (block.type === "h2") return <h2 key={key}>{block.text}</h2>;
        if (block.type === "h3") return <h3 key={key}>{block.text}</h3>;
        if (block.type === "quote") return <blockquote key={key}>{block.text}</blockquote>;
        if (block.type === "hr") return <hr key={key} />;
        if (block.type === "space") return <div key={key} className="markdown-space" />;
        if (block.type === "list") {
          return (
            <ul key={key}>
              {block.items.map((item, itemIndex) => <li key={`${key}-${itemIndex}`}>{renderInlineText(item, `${key}-li-${itemIndex}`)}</li>)}
            </ul>
          );
        }
        if (block.type === "table") {
          const [header = [], divider = [], ...body] = block.rows;
          const rows = divider.every((cell) => /^:?-{3,}:?$/.test(cell)) ? body : [divider, ...body].filter((row) => row.length);
          const tableClass = tableProfile(block.rows);
          if (tableClass === "probe-table") {
            return <ProbeReportBlocks header={header} rows={rows} blockKey={key} key={key} />;
          }
          return (
            <div className={`table-wrap ${tableClass}`} key={key}>
              <table>
                <thead>
                  <tr>{header.map((cell, cellIndex) => <th key={`${key}-h-${cellIndex}`}>{renderTableCell(cell, `${key}-h-${cellIndex}`)}</th>)}</tr>
                </thead>
                <tbody>
                  {rows.map((row, rowIndex) => (
                    <tr key={`${key}-r-${rowIndex}`}>
                      {row.map((cell, cellIndex) => <td key={`${key}-c-${rowIndex}-${cellIndex}`}>{renderTableCell(cell, `${key}-c-${rowIndex}-${cellIndex}`)}</td>)}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          );
        }
        if (block.type === "code") {
          return (
            <pre key={key} className="code-block">
              <code>{block.code}</code>
            </pre>
          );
        }
        return <p key={key}>{block.text}</p>;
      })}
    </article>
  );
}

function App() {
  const rootRef = useRef(null);
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
    const result = await api().getDocument(String(item.id));
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
    const result = await api().getRequirement(String(item.id));
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
        const result = await api().getRequirement(String(item.id));
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
    const configResult = await api().config();
    let activeConfig = configResult;
    const storedDbPath = readStoredDbPath();
    if (configResult.ok && storedDbPath && storedDbPath !== configResult.dbPath) {
      activeConfig = await api().setDbPath(storedDbPath);
    }
    if (activeConfig.ok) {
      setConfig(activeConfig);
      setDbPathInput(activeConfig.dbPath || "");
    }
    const listResult = await api().listRequirements(500);
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
      const result = await api().search(text, 24);
      if (!cancelled) setSearchResults(result.ok ? result.results || [] : []);
    };
    run();
    return () => {
      cancelled = true;
    };
  }, [deferredQuery]);

  const statusOptions = useMemo(() => {
    const values = new Set(requirements.map((item) => normalizeStatus(item.status)));
    return ["全部", ...Array.from(values).sort((a, b) => a.localeCompare(b, "zh-CN"))];
  }, [requirements]);

  const filteredRequirements = useMemo(() => {
    const text = deferredQuery.trim().toLowerCase();
    return requirements.filter((item) => {
      const matchesStatus = statusFilter === "全部" || normalizeStatus(item.status) === statusFilter;
      const haystack = `${item.slug} ${item.title} ${item.summary} ${item.root_path} ${projectOf(item)}`.toLowerCase();
      return matchesStatus && (!text || haystack.includes(text));
    });
  }, [requirements, deferredQuery, statusFilter]);

  const groupedDocuments = useMemo(() => {
    return [...documents].sort((a, b) => {
      const stage = String(a.document_type).localeCompare(String(b.document_type));
      return stage || String(a.relative_path).localeCompare(String(b.relative_path));
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
      const docs = documentMap.get(String(requirement.id)) || [];
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
    ? markdownProfile(selectedDocument.content)
        .split(" ")
        .filter(Boolean)
        .map((name) => `reader-${name}`)
        .join(" ")
    : "";

  const applyDbPath = async () => {
    const nextDbPath = dbPathInput.trim();
    setBusy(true);
    setMessage("正在切换 SQLite 索引库…");
    const result = await api().setDbPath(nextDbPath);
    if (!result.ok) {
      setMessage(result.message || "切换索引库失败。");
      setBusy(false);
      return false;
    }
    try {
      window.localStorage.setItem(DB_PATH_KEY, result.dbPath || nextDbPath);
    } catch (_error) {
      // localStorage 不可用时仅在本次 Electron 进程内生效。
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
    const result = await api().reindex();
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
    const unsubscribe = api().onOpenIndexDialog?.(openIndexDialog);
    return () => {
      if (typeof unsubscribe === "function") unsubscribe();
    };
  }, [openIndexDialog]);

  useEffect(() => {
    const handleIndexShortcut = (event) => {
      if (!(event.ctrlKey || event.metaKey) || !event.shiftKey || event.key.toLowerCase() !== "u") return;
      event.preventDefault();
      openIndexDialog();
    };
    window.addEventListener("keydown", handleIndexShortcut);
    return () => window.removeEventListener("keydown", handleIndexShortcut);
  }, [openIndexDialog]);

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
    <div className={`app-shell ${isResizingTree ? "is-resizing-tree" : ""}`} ref={rootRef}>
      <main
        id="main-content"
        className={`workspace-grid ${isTreeCollapsed ? "is-tree-collapsed" : ""}`}
        style={{
          "--tree-pane-width": `${isTreeCollapsed ? 52 : treePaneWidth}px`,
          "--tree-resizer-width": isTreeCollapsed ? "0rem" : "0.42rem",
        }}
      >
        <Paper
          component="section"
          elevation={0}
          className={`workspace-pane tree-pane ${isTreeCollapsed ? "is-collapsed" : ""}`}
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
                  <h2 id="tree-heading">项目文档树</h2>
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
              className="text-input"
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
              className="text-input"
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

        <Paper component="section" elevation={0} className={`workspace-pane reader-pane reader-pane-wide ${selectedReaderMode}`} aria-labelledby="reader-heading">
          <div className="pane-heading reader-heading">
            <div className="min-w-0">
              <h2 id="reader-heading">{documentDisplayTitle(selectedDocument, selectedRequirement)}</h2>
              <p translate="no">{selectedDocument?.relative_path || selectedRequirement?.root_path || message}</p>
            </div>
          </div>
          <dl className="reader-summary-strip">
            <div>
              <dt>项目</dt>
              <dd translate="no">{activeProject || "-"}</dd>
            </div>
            <div>
              <dt>需求</dt>
              <dd>{selectedRequirement ? shortRequirementName(selectedRequirement) : "-"}</dd>
            </div>
            <div>
              <dt>阶段文档</dt>
              <dd>{new Intl.NumberFormat(navigator.languages).format(groupedDocuments.length)}</dd>
            </div>
            <div className="reader-status-summary">
              <dt>状态</dt>
              <dd>{normalizeStatus(selectedRequirement?.status)}</dd>
            </div>
          </dl>
          {selectedDocument && (
            <dl className="metadata-grid">
              <div><dt>项目</dt><dd translate="no">{activeProject}</dd></div>
              <div><dt>类型</dt><dd>{stageLabel(selectedDocument.document_type)}</dd></div>
              <div><dt>大小</dt><dd>{bytes(selectedDocument.size_bytes)} bytes</dd></div>
              <div><dt>更新</dt><dd>{displayDate(selectedDocument.updated_at)}</dd></div>
            </dl>
          )}
          <MarkdownText content={selectedDocument?.content || ""} />
        </Paper>
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
        PaperProps={{ className: `index-dialog-paper index-dialog-${indexDialogMode}` }}
      >
        <DialogTitle className="index-dialog-title">
          <span>索引维护</span>
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
                <span>更新数据库</span>
                <small>切换 SQLite 文件路径，应用后重新加载项目树。</small>
              </button>
            </div>
          ) : (
            <div className="index-db-form">
              <TextField
                id="dialog-db-path-input"
                name="dialog-db-path-input"
                className="text-input"
                label="SQLite 索引库地址"
                value={dbPathInput}
                onChange={(event) => setDbPathInput(event.target.value)}
                onKeyDown={(event) => {
                  if (event.key === "Enter") applyDbPathFromDialog();
                }}
                placeholder="输入 SQLite 文件路径…"
                autoComplete="off"
                autoFocus
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
