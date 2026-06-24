export function markdownProfile(content, documentType = "") {
  const text = content || "";
  const isWorkPhp = text.includes("# 执行结果") && text.includes("执行命令：`docker exec work php");
  const isProbeDocument = documentType === "probe_result";
  const isProbe = isProbeDocument && (text.includes("| 接口地址 | 入参 | 出参 |") || text.includes("probe_result") || text.includes("management_backend_cleanup_probe"));
  return [
    isWorkPhp ? "work-php-report" : "",
    isProbe ? "probe-report" : "",
  ].filter(Boolean).join(" ");
}

export function tableProfile(rows) {
  const headerText = (rows[0] || []).join(" ");
  if (headerText.includes("接口地址") && headerText.includes("测试结果") && headerText.includes("关联脚本文件")) {
    return "probe-table";
  }
  return "";
}
