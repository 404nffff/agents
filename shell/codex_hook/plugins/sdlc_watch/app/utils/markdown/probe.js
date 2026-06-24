function normalizedProbeHeader(value) {
  return String(value || "").replace(/\s+/g, "");
}

function decodeProbeText(value) {
  return String(value || "")
    .replace(/&quot;/g, "\"")
    .replace(/&#39;/g, "'")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">");
}

export function probeCell(row, header, names) {
  const targets = new Set(names.map(normalizedProbeHeader));
  const index = header.findIndex((item) => targets.has(normalizedProbeHeader(item)));
  return index >= 0 ? row[index] || "" : "";
}

export function shortCellText(value, fallback = "") {
  return decodeProbeText(value)
    .split(/<br\s*\/?>/i)[0]
    .replace(/`/g, "")
    .trim() || fallback;
}

export function endpointMethod(value) {
  const text = shortCellText(value, "API");
  const match = text.match(/\b(GET|POST|PUT|PATCH|DELETE|DEL)\b/i);
  if (!match) return "API";
  return match[1].toUpperCase() === "DEL" ? "DEL" : match[1].toUpperCase();
}

export function endpointPath(value) {
  return shortCellText(value, "接口地址").replace(/\b(GET|POST|PUT|PATCH|DELETE|DEL)\b/i, "").trim();
}

export function probePathKey(value) {
  return endpointPath(value).split("?")[0].replace(/\/+$/g, "") || endpointPath(value);
}

export function endpointLeafName(value) {
  const path = endpointPath(value);
  const clean = path.split("?")[0].replace(/\/+$/g, "");
  return clean.split("/").filter(Boolean).pop() || path;
}

export function probeBlockId(blockKey, rowIndex) {
  return `probe-${blockKey}-${rowIndex}`.replace(/[^a-zA-Z0-9_-]/g, "-");
}

export function shortProbeAnchor(value, index) {
  const text = decodeProbeText(value).split(/<br\s*\/?>/i)[0].replace(/`/g, "").trim();
  return text || `接口 ${index + 1}`;
}

export function shortProbeTime(value) {
  return decodeProbeText(value)
    .replace(/<br\s*\/?>/gi, " ")
    .replace(/`/g, "")
    .trim();
}

export function probeTimeRank(value) {
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

export function probeTableRows(tableRows) {
  const [header = [], divider = [], ...body] = tableRows;
  const rows = divider.every((cell) => /^:?-{3,}:?$/.test(cell)) ? body : [divider, ...body].filter((row) => row.length);
  return { header, rows };
}

export function buildProbeBlocks(header, rows, blockKey) {
  return rows
    .map((row, rowIndex) => {
      const requestTime = probeCell(row, header, ["请求时间"]);
      return {
        id: probeBlockId(blockKey, rowIndex),
        rowIndex,
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
}

export function buildProbeGroups(blocks) {
  const groupMap = new Map();
  for (const block of blocks) {
    const key = probePathKey(block.endpoint);
    if (!groupMap.has(key)) {
      groupMap.set(key, {
        key,
        path: endpointPath(block.endpoint),
        leafName: endpointLeafName(block.endpoint),
        blocks: [],
        latestTimeRank: block.requestTimeRank || 0,
      });
    }
    const group = groupMap.get(key);
    group.blocks.push(block);
    group.latestTimeRank = Math.max(group.latestTimeRank, block.requestTimeRank || 0);
  }
  return [...groupMap.values()]
    .map((group) => ({
      ...group,
      blocks: [...group.blocks].sort((left, right) => right.requestTimeRank - left.requestTimeRank || left.rowIndex - right.rowIndex),
    }))
    .sort((left, right) => right.latestTimeRank - left.latestTimeRank || left.path.localeCompare(right.path));
}
