import React from "react";

function decodeCellEntities(value) {
  return String(value || "")
    .replace(/&quot;/g, "\"")
    .replace(/&#39;/g, "'")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">");
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

function prettyJson(line) {
  const text = decodeCellEntities(line).trim().replace(/^`|`$/g, "");
  if (!/^[{\[]/.test(text)) return "";
  try {
    return JSON.stringify(JSON.parse(text), null, 2);
  } catch (_error) {
    return "";
  }
}

export function renderInlineText(text, keyPrefix) {
  const parts = decodeCellEntities(text).split(/(`[^`]+`)/g);
  return parts.map((part, index) => {
    if (part.startsWith("`") && part.endsWith("`")) {
      return <code className="inline-code" key={`${keyPrefix}-code-${index}`}>{part.slice(1, -1)}</code>;
    }
    return <React.Fragment key={`${keyPrefix}-text-${index}`}>{part}</React.Fragment>;
  });
}

export function renderTableCell(cell, keyPrefix) {
  return decodeCellEntities(cell).split(/<br\s*\/?>/i).map((line, index) => {
    const formattedJson = prettyJson(line);
    if (formattedJson) {
      return (
        <pre className={`cell-line cell-json cell-json-pre ${cellLineClass(line)}`} key={`${keyPrefix}-line-${index}`}>
          <code>{formattedJson}</code>
        </pre>
      );
    }
    return (
      <span className={`cell-line ${cellLineClass(line)}`} key={`${keyPrefix}-line-${index}`}>
        {renderInlineText(line, `${keyPrefix}-${index}`)}
      </span>
    );
  });
}
