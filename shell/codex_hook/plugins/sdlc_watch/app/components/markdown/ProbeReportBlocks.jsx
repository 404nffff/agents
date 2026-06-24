import React, { useMemo, useState } from "react";
import Chip from "@mui/material/Chip";
import Paper from "@mui/material/Paper";
import {
  buildProbeGroups,
  buildProbeBlocks,
  endpointLeafName,
  endpointMethod,
  endpointPath,
  shortCellText,
  shortProbeAnchor,
  shortProbeTime,
} from "../../utils/markdown/probe";
import { renderTableCell } from "./renderers";

const PROBE_TABS = [
  { key: "request", label: "请求 JSON" },
  { key: "response", label: "响应 JSON" },
  { key: "test", label: "测试说明" },
];

function resultChipColor(result) {
  const text = String(result || "");
  if (/通过|成功|passed/i.test(text)) return "success";
  if (/失败|error|failed|超时|异常/i.test(text)) return "error";
  if (/风险|warning|未执行|未配置/i.test(text)) return "warning";
  return "default";
}

export function ProbeReportBlocks({ header, rows, blockKey, probeViewMode = "v1", selectedProbePath = "" }) {
  const blocks = useMemo(() => buildProbeBlocks(header, rows, blockKey), [blockKey, header, rows]);
  const activeGroup = useMemo(() => {
    if (probeViewMode !== "v2") return null;
    const groups = buildProbeGroups(blocks);
    return groups.find((group) => group.key === selectedProbePath) || groups[0] || null;
  }, [blocks, probeViewMode, selectedProbePath]);
  const visibleBlocks = probeViewMode === "v2" ? activeGroup?.blocks || [] : blocks;

  return (
    <section className={`probe-block-layout ${probeViewMode === "v2" ? "probe-block-layout-v2" : ""}`} aria-label="链路探针结果">
      {probeViewMode === "v2" && activeGroup && (
        <header className="probe-path-group-header">
          <div>
            <span>当前接口路径</span>
            <h3>{activeGroup.path}</h3>
          </div>
          <strong>{activeGroup.blocks.length} 次请求</strong>
        </header>
      )}
      <div className="probe-block-list">
        {visibleBlocks.map((block, index) => (
          <ProbeCaseCard block={block} index={index} key={block.id} />
        ))}
      </div>
    </section>
  );
}

function ProbeCaseCard({ block, index }) {
  const [activeTab, setActiveTab] = useState("request");

  return (
    <Paper className="probe-case-card" id={block.id} elevation={0}>
      <div className={`probe-case-rail probe-case-rail-${resultChipColor(block.result)}`} aria-hidden="true" />
      <header className="probe-case-header probe-detail-header">
        <div className="probe-case-title">
          <div className="probe-chip-row">
            <Chip className="probe-index-chip" label={`接口 ${String(index + 1).padStart(3, "0")}`} size="small" />
            <Chip className={`probe-method-chip probe-method-${endpointMethod(block.endpoint).toLowerCase()}`} label={endpointMethod(block.endpoint)} size="small" />
            <Chip
              className="probe-result-chip"
              color={resultChipColor(block.result)}
              label={shortCellText(block.result, "待检查").slice(0, 18)}
              size="small"
              variant="filled"
            />
          </div>
          <h4>{endpointPath(block.endpoint)}</h4>
        </div>
        <div className="probe-case-meta" aria-label="链路探针元信息">
          <div className="probe-meta-chips">
            {block.requestTime && (
              <Chip
                className="probe-time-chip"
                label={shortProbeTime(block.requestTime)}
                size="small"
                variant="filled"
              />
            )}
          </div>
        </div>
      </header>
      <div className="probe-inspector-body">
        <section className="probe-basic-card" aria-label="接口基本信息">
          <div className="probe-basic-row probe-basic-row-endpoint">
            <h5>接口地址</h5>
            <div className="probe-basic-value probe-endpoint-value">
              <span className={`probe-method-pill probe-method-${endpointMethod(block.endpoint).toLowerCase()}`}>{endpointMethod(block.endpoint)}</span>
              <strong>{endpointPath(block.endpoint)}</strong>
            </div>
          </div>
          <div className="probe-basic-row">
            <h5>测试条件</h5>
            <div className="probe-basic-value">{shortCellText(block.condition, "-")}</div>
          </div>
          <div className="probe-basic-row">
            <h5>边界条件</h5>
            <div className="probe-basic-value">{shortCellText(block.boundary, "-")}</div>
          </div>
          <div className="probe-basic-row">
            <h5>测试结果</h5>
            <div className="probe-basic-value">{shortCellText(block.result, "-")}</div>
          </div>
          <div className="probe-basic-row">
            <h5>请求时间</h5>
            <div className="probe-basic-value">{shortProbeTime(block.requestTime) || "-"}</div>
          </div>
          <div className="probe-basic-row">
            <h5>关联脚本文件</h5>
            <div className="probe-basic-value">{shortCellText(block.script, "-")}</div>
          </div>
        </section>
        <section className={`probe-json-card probe-json-card-${activeTab}`} aria-label="链路请求响应">
          <div className="probe-json-main">
            <div className="probe-tabs" role="tablist" aria-label="接口详情切换">
              {PROBE_TABS.map((tab) => (
                <button
                  type="button"
                  role="tab"
                  aria-selected={activeTab === tab.key}
                  className={activeTab === tab.key ? "is-active" : ""}
                  key={tab.key}
                  onClick={() => setActiveTab(tab.key)}
                >
                  {tab.label}
                </button>
              ))}
            </div>
            {activeTab === "request" && (
              <section className="probe-field probe-field-io probe-field-input" role="tabpanel">
                <div className="probe-payload-title">
                  <h5>请求 JSON</h5>
                  <span>Request</span>
                </div>
                <div className="probe-field-body probe-payload-body">{renderTableCell(block.input, `${block.id}-input`)}</div>
              </section>
            )}
            {activeTab === "response" && (
              <section className="probe-field probe-field-io probe-field-output" role="tabpanel">
                <div className="probe-payload-title">
                  <h5>响应 JSON</h5>
                  <span>Response</span>
                </div>
                <div className="probe-field-body probe-payload-body">{renderTableCell(block.output, `${block.id}-output`)}</div>
              </section>
            )}
            {activeTab === "test" && (
              <section className="probe-test-note" role="tabpanel">
                <h5>测试说明</h5>
                <ol>
                  <li>{renderTableCell(block.condition, `${block.id}-note-condition`)}</li>
                  <li>{renderTableCell(block.boundary, `${block.id}-note-boundary`)}</li>
                  <li>{renderTableCell(block.result, `${block.id}-note-result`)}</li>
                </ol>
              </section>
            )}
          </div>
        </section>
      </div>
    </Paper>
  );
}

export function ProbeAnchorNav({ blocks, probeViewMode = "v1", selectedProbePath = "", onSelectProbePath }) {
  const [query, setQuery] = useState("");
  const [open, setOpen] = useState(false);
  const groups = useMemo(() => buildProbeGroups(blocks), [blocks]);
  const filteredBlocks = useMemo(() => {
    const keyword = query.trim().toLowerCase();
    if (!keyword) return blocks;
    return blocks.filter((block, index) => {
      const haystack = [
        String(index + 1).padStart(2, "0"),
        endpointMethod(block.endpoint),
        endpointPath(block.endpoint),
        endpointLeafName(block.endpoint),
        shortProbeTime(block.requestTime),
      ].join(" ").toLowerCase();
      return haystack.includes(keyword);
    });
  }, [blocks, query]);
  const filteredGroups = useMemo(() => {
    const keyword = query.trim().toLowerCase();
    if (!keyword) return groups;
    return groups.filter((group, index) => {
      const latestTime = shortProbeTime(group.blocks[0]?.requestTime);
      const haystack = [
        String(index + 1).padStart(2, "0"),
        group.path,
        group.leafName,
        latestTime,
        `${group.blocks.length}次`,
      ].join(" ").toLowerCase();
      return haystack.includes(keyword);
    });
  }, [groups, query]);

  const scrollToProbeBlock = (event, id) => {
    event.preventDefault();
    const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    document.getElementById(id)?.scrollIntoView({ block: "start", behavior: reduceMotion ? "auto" : "smooth" });
  };

  return (
    <Paper component="nav" className={`floating-anchor-nav probe-anchor-nav ${open ? "is-open" : ""}`} aria-label="链路探针接口定位" elevation={0}>
      <button
        type="button"
        className="floating-anchor-trigger"
        aria-expanded={open}
        onClick={() => setOpen((current) => !current)}
      >
        接口定位
      </button>
      <div className="floating-anchor-panel">
        <h4>{probeViewMode === "v2" ? "接口路径" : "接口定位"}</h4>
        <label className="probe-anchor-search">
          <span>{probeViewMode === "v2" ? "搜索接口路径" : "搜索接口地址或编号"}</span>
          <input
            type="search"
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder={probeViewMode === "v2" ? "搜索接口路径" : "搜索接口地址或编号"}
          />
        </label>
        {probeViewMode === "v2"
          ? filteredGroups.map((group, index) => (
              <button
                type="button"
                className={`probe-path-anchor ${selectedProbePath === group.key ? "is-active" : ""}`}
                key={`${group.key}-anchor`}
                onClick={() => {
                  onSelectProbePath?.(group.key);
                  setOpen(false);
                }}
              >
                <span className="probe-nav-index">{String(index + 1).padStart(2, "0")}</span>
                <span className="probe-path-count">{group.blocks.length}</span>
                <span className="probe-anchor-copy">
                  <strong title={group.path}>{group.leafName || group.path}</strong>
                  <em>{shortProbeTime(group.blocks[0]?.requestTime) || "无请求时间"}</em>
                </span>
              </button>
            ))
          : filteredBlocks.map((block, index) => (
              <a href={`#${block.id}`} key={`${block.id}-anchor`} onClick={(event) => scrollToProbeBlock(event, block.id)}>
                <span className="probe-nav-index">{String(block.rowIndex + 1).padStart(2, "0")}</span>
                <span className={`probe-method-mini probe-method-${endpointMethod(block.endpoint).toLowerCase()}`}>{endpointMethod(block.endpoint)}</span>
                <span className="probe-anchor-copy">
                  <strong title={endpointPath(block.endpoint)}>{endpointLeafName(block.endpoint) || shortProbeAnchor(block.endpoint, index)}</strong>
                  {block.requestTime && <em>{shortProbeTime(block.requestTime)}</em>}
                </span>
              </a>
            ))}
        {probeViewMode === "v2" && !filteredGroups.length && <p className="probe-anchor-empty">没有匹配路径</p>}
        {probeViewMode !== "v2" && !filteredBlocks.length && <p className="probe-anchor-empty">没有匹配接口</p>}
      </div>
    </Paper>
  );
}
