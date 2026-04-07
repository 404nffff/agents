#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_DEPLOY_DIR="${SCRIPT_DIR}"

REMOTE_HOST=""
REMOTE_USER="root"
REMOTE_PORT="22"
REMOTE_DIR=".cpa_deploy"
SSH_IDENTITY=""
DRY_RUN="false"

declare -a FORWARD_ARGS=()

usage() {
  cat <<EOF
用法:
  ./${SCRIPT_NAME} --host <ip_or_host> [选项] [-- build.sh参数]

说明:
  通过 ssh/scp 将当前目录下的 build.sh 与 config/ 复制到远端，
  然后在远端执行:
    bash ${REMOTE_DIR}/build.sh install

选项:
  --host <ip_or_host>        远端主机，必填
  --user <user>              远端 ssh 用户，默认 root
  --port <port>              远端 ssh 端口，默认 22
  --identity <path>          ssh 私钥路径
  --remote-dir <dir>         远端脚本目录，默认 ${REMOTE_DIR}
  --dry-run                  仅打印命令，不实际执行
  -h, --help                 显示帮助

示例:
  ./${SCRIPT_NAME} --host 1.2.3.4
  ./${SCRIPT_NAME} --host 1.2.3.4 --user ubuntu -- --skip-fail2ban
  ./${SCRIPT_NAME} --host 1.2.3.4 --port 2222 --identity ~/.ssh/id_rsa -- --dry-run
EOF
}

log() {
  printf '[%s] %s\n' "${SCRIPT_NAME}" "$*"
}

err() {
  printf '[%s] ERROR: %s\n' "${SCRIPT_NAME}" "$*" >&2
}

die() {
  err "$*"
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

run_cmd() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    log "DRY-RUN: $*"
    return 0
  fi
  "$@"
}

validate_port() {
  local value="$1"
  [[ "${value}" =~ ^[0-9]+$ ]] || return 1
  (( value >= 1 && value <= 65535 ))
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --host)
        [[ $# -ge 2 ]] || die "--host 缺少参数"
        REMOTE_HOST="$2"
        shift 2
        ;;
      --user)
        [[ $# -ge 2 ]] || die "--user 缺少参数"
        REMOTE_USER="$2"
        shift 2
        ;;
      --port)
        [[ $# -ge 2 ]] || die "--port 缺少参数"
        REMOTE_PORT="$2"
        shift 2
        ;;
      --identity)
        [[ $# -ge 2 ]] || die "--identity 缺少参数"
        SSH_IDENTITY="$2"
        shift 2
        ;;
      --remote-dir)
        [[ $# -ge 2 ]] || die "--remote-dir 缺少参数"
        REMOTE_DIR="$2"
        shift 2
        ;;
      --dry-run)
        DRY_RUN="true"
        shift
        ;;
      --)
        shift
        FORWARD_ARGS=("$@")
        return 0
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "未知参数: $1"
        ;;
    esac
  done
}

ensure_requirements() {
  [[ -n "${REMOTE_HOST}" ]] || die "必须提供 --host"
  validate_port "${REMOTE_PORT}" || die "ssh 端口非法: ${REMOTE_PORT}"
  command_exists ssh || die "未找到 ssh"
  command_exists scp || die "未找到 scp"
  [[ -f "${LOCAL_DEPLOY_DIR}/build.sh" ]] || die "未找到本地部署脚本: ${LOCAL_DEPLOY_DIR}/build.sh"
  [[ -d "${LOCAL_DEPLOY_DIR}/config" ]] || die "未找到本地配置目录: ${LOCAL_DEPLOY_DIR}/config"
  if [[ -n "${SSH_IDENTITY}" && ! -f "${SSH_IDENTITY}" ]]; then
    die "ssh 私钥不存在: ${SSH_IDENTITY}"
  fi
}

build_ssh_args() {
  declare -ga SSH_ARGS SCP_ARGS

  SSH_ARGS=(-p "${REMOTE_PORT}" -o BatchMode=no -o StrictHostKeyChecking=accept-new)
  SCP_ARGS=(-P "${REMOTE_PORT}" -o BatchMode=no -o StrictHostKeyChecking=accept-new)

  if [[ -n "${SSH_IDENTITY}" ]]; then
    SSH_ARGS+=(-i "${SSH_IDENTITY}")
    SCP_ARGS+=(-i "${SSH_IDENTITY}")
  fi
}

join_forward_args() {
  local joined=""
  local item

  if [[ "${#FORWARD_ARGS[@]}" -eq 0 ]]; then
    printf '%s' ""
    return 0
  fi

  for item in "${FORWARD_ARGS[@]}"; do
    printf -v joined '%s %q' "${joined}" "${item}"
  done

  printf '%s' "${joined}"
}

sync_files() {
  local remote_target="${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/"

  log "同步 build.sh 与 config/ 到远端 ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}"
  run_cmd ssh "${SSH_ARGS[@]}" "${REMOTE_USER}@${REMOTE_HOST}" "mkdir -p ${REMOTE_DIR@Q}"
  run_cmd scp "${SCP_ARGS[@]}" "${LOCAL_DEPLOY_DIR}/build.sh" "${remote_target}"
  run_cmd scp "${SCP_ARGS[@]}" -r "${LOCAL_DEPLOY_DIR}/config" "${remote_target}"
  run_cmd ssh "${SSH_ARGS[@]}" "${REMOTE_USER}@${REMOTE_HOST}" "chmod +x ${REMOTE_DIR@Q}/build.sh"
}

run_remote_install() {
  local forward_args remote_cmd

  forward_args="$(join_forward_args)"
  remote_cmd="cd ${REMOTE_DIR@Q} && bash ./build.sh install${forward_args}"

  log "在远端执行安装命令"
  run_cmd ssh "${SSH_ARGS[@]}" -t "${REMOTE_USER}@${REMOTE_HOST}" "${remote_cmd}"
}

main() {
  parse_args "$@"
  ensure_requirements
  build_ssh_args

  log "远端主机: ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PORT}"
  log "远端目录: ${REMOTE_DIR}"

  sync_files
  run_remote_install
}

main "$@"
