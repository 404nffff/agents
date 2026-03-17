#!/usr/bin/env bash
set -euo pipefail

# Claude Code skills 安装脚本
# 将 grok-skill 安装到 Claude Code 的 skills 目录

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_name="grok-search"
dest_root="${HOME}/.claude/skills"
dest="${dest_root}/${skill_name}"

# 创建 skills 目录
mkdir -p "${dest_root}"

# 创建临时目录保存配置文件
tmp_preserve="$(mktemp -d)"
cleanup() {
  rm -rf "${tmp_preserve}"
}
trap cleanup EXIT

# 保存现有配置文件
for name in config.json config.local.json; do
  if [[ -f "${dest}/${name}" ]]; then
    cp "${dest}/${name}" "${tmp_preserve}/${name}"
  fi
done

# 删除旧的安装目录
if [[ -d "${dest}" ]]; then
  rm -rf "${dest}"
fi

# 创建新的安装目录
mkdir -p "${dest}"

# 复制 skill 文件
cp "${repo_root}/SKILL.md" "${dest}/"
cp "${repo_root}/README.md" "${dest}/"
cp "${repo_root}/install.sh" "${dest}/"
cp "${repo_root}/install_cc.sh" "${dest}/"
cp "${repo_root}/install.ps1" "${dest}/"
cp "${repo_root}/configure.ps1" "${dest}/"
cp "${repo_root}/config.json" "${dest}/"

# 如果有 scripts 目录，复制它
if [[ -d "${repo_root}/scripts" ]]; then
  cp -R "${repo_root}/scripts" "${dest}/"
fi

# 恢复保存的配置文件
for name in config.json config.local.json; do
  if [[ -f "${tmp_preserve}/${name}" ]]; then
    cp "${tmp_preserve}/${name}" "${dest}/${name}"
  fi
done

echo "✓ Grok skill 已安装到 Claude Code"
echo "  安装路径: ${dest}"
echo ""
echo "使用方法:"
echo "  在 Claude Code 中输入 /grok-search 或使用 Skill 工具调用"
