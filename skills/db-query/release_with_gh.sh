#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="${SCRIPT_DIR}"
BIN_DIR="${SKILL_DIR}/bin"

ASSET_LINUX="${BIN_DIR}/db-query-linux-amd64"
ASSET_WINDOWS="${BIN_DIR}/db-query-windows-amd64.exe"

trim() {
  local s="${1:-}"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "${s}"
}

normalize_repo() {
  local raw="$1"
  raw="${raw%.git}"
  raw="${raw#https://github.com/}"
  raw="${raw#http://github.com/}"
  raw="${raw#git@github.com:}"
  printf '%s' "${raw}"
}

detect_repo_from_git() {
  local top remote_url
  top="$(git -C "${SKILL_DIR}" rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -z "${top}" ]]; then
    return 1
  fi
  remote_url="$(git -C "${top}" remote get-url origin 2>/dev/null || true)"
  if [[ -z "${remote_url}" ]]; then
    return 1
  fi
  normalize_repo "${remote_url}"
}

detect_latest_tag() {
  local repo="$1"
  local tag top

  tag="$(gh release list --repo "${repo}" --limit 1 --json tagName --jq '.[0].tagName' 2>/dev/null || true)"
  tag="$(trim "${tag}")"
  if [[ -n "${tag}" && "${tag}" != "null" ]]; then
    printf '%s' "${tag}"
    return 0
  fi

  top="$(git -C "${SKILL_DIR}" rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -n "${top}" ]]; then
    tag="$(git -C "${top}" tag --sort=-v:refname | head -n 1 || true)"
    tag="$(trim "${tag}")"
    if [[ -n "${tag}" ]]; then
      printf '%s' "${tag}"
      return 0
    fi
  fi

  printf '%s' "v0.1.0"
}

require_file() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    echo "ERROR: file not found: ${path}" >&2
    exit 1
  fi
}

print_token_permission_hint() {
  cat >&2 <<'EOF'
Hint: 当前 token 可能缺少发布 Release 权限。
需要至少满足以下任一组合：

1) Fine-grained PAT
   - Repository access: 包含目标仓库
   - Repository permissions:
     - Contents: Read and write
     - Metadata: Read

2) Classic PAT
   - 私有仓库: repo
   - 公有仓库: public_repo（或 repo）

另外请确认：
- 账号已对该组织仓库完成 SSO 授权（若组织启用 SSO）
- gh 当前登录的 token 是你期望的那个（gh auth status）
EOF
}

run_gh_or_hint() {
  local output status
  set +e
  output="$("$@" 2>&1)"
  status=$?
  set -e

  if [[ -n "${output}" ]]; then
    printf '%s\n' "${output}"
  fi

  if [[ ${status} -ne 0 ]]; then
    if [[ "${output}" == *"Resource not accessible by personal access token"* ]] || [[ "${output}" == *"HTTP 403"* ]]; then
      print_token_permission_hint
    fi
  fi

  return "${status}"
}

if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: gh not found. Please install GitHub CLI first." >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "ERROR: gh auth not ready. Run: gh auth login" >&2
  exit 1
fi

REPO="$(trim "${2:-${GITHUB_REPO:-}}")"
if [[ -z "${REPO}" ]]; then
  REPO="$(detect_repo_from_git || true)"
fi
REPO="$(normalize_repo "${REPO}")"
if [[ -z "${REPO}" ]]; then
  echo "ERROR: cannot determine GitHub repo. Pass as second arg or set GITHUB_REPO." >&2
  echo "Usage: $0 <tag> [owner/repo]" >&2
  exit 1
fi

DEFAULT_TAG="$(detect_latest_tag "${REPO}")"
TAG="$(trim "${1:-}")"
if [[ -z "${TAG}" ]]; then
  read -r -p "请输入发布 tag（默认: ${DEFAULT_TAG}）: " TAG
  TAG="$(trim "${TAG}")"
fi
if [[ -z "${TAG}" ]]; then
  TAG="${DEFAULT_TAG}"
fi

require_file "${ASSET_LINUX}"
require_file "${ASSET_WINDOWS}"

echo "Repo: ${REPO}"
echo "Tag:  ${TAG}"
echo "Assets:"
echo "  - ${ASSET_LINUX}"
echo "  - ${ASSET_WINDOWS}"

if gh release view "${TAG}" --repo "${REPO}" >/dev/null 2>&1; then
  echo "Release exists, uploading assets with --clobber ..."
  run_gh_or_hint gh release upload "${TAG}" \
    "${ASSET_LINUX}" \
    "${ASSET_WINDOWS}" \
    --repo "${REPO}" \
    --clobber
else
  echo "Release not found, creating release ..."
  run_gh_or_hint gh release create "${TAG}" \
    "${ASSET_LINUX}" \
    "${ASSET_WINDOWS}" \
    --repo "${REPO}" \
    --title "${TAG}" \
    --notes "db-query release binaries"
fi

echo "Done: https://github.com/${REPO}/releases/tag/${TAG}"
