import React, { useMemo } from "react";
import { parseMarkdownBlocks } from "../../utils/markdown/parser";
import { markdownProfile, tableProfile } from "../../utils/markdown/profile";
import { ProbeReportBlocks } from "./ProbeReportBlocks";
import { renderInlineText, renderTableCell } from "./renderers";

export function headingAnchorId(index) {
  return `markdown-heading-${index}`;
}

export function MarkdownText({ content, documentType = "", omitFirstHeading = false, probeViewMode = "v1", selectedProbePath = "" }) {
  const blocks = useMemo(() => parseMarkdownBlocks(content), [content]);
  const profileClass = useMemo(() => markdownProfile(content, documentType), [content, documentType]);
  const firstContentBlockIndex = useMemo(() => blocks.findIndex((block) => block.type !== "space"), [blocks]);

  if (!content) {
    return (
      <div className="empty-state" role="status" aria-live="polite">
        <p className="empty-title">未选择文档</p>
        <p className="empty-detail">选择阶段文档后会在这里显示全文。</p>
      </div>
    );
  }

  return (
    <article className={`markdown-view ${profileClass}`}>
      {blocks.map((block, index) => {
        const key = `${block.type}-${index}`;
        if (omitFirstHeading && index === firstContentBlockIndex && block.type === "h1") return null;
        if (block.type === "h1") return <h1 id={headingAnchorId(index)} key={key}>{block.text}</h1>;
        if (block.type === "h2") return <h2 id={headingAnchorId(index)} key={key}>{block.text}</h2>;
        if (block.type === "h3") return <h3 id={headingAnchorId(index)} key={key}>{block.text}</h3>;
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
          const currentTableProfile = tableProfile(block.rows);
          if (currentTableProfile === "probe-table") {
            return (
              <ProbeReportBlocks
                header={header}
                rows={rows}
                blockKey={key}
                probeViewMode={probeViewMode}
                selectedProbePath={selectedProbePath}
                key={key}
              />
            );
          }
          return (
            <div className={`table-wrap ${currentTableProfile}`} key={key}>
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
