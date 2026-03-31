#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SSHD_CONFIG_PATH="${SSHD_CONFIG_PATH:-/etc/ssh/sshd_config}"
USE_DRY_RUN="false"
ACTION_MENU="false"
ACTION_STATUS="false"
ENABLE_UFW="false"
SET_SSH_PORT=""
SET_PASSWORD_AUTH=""
SET_ROOT_LOGIN=""
SSHD_BACKUP_PATH=""

declare -a ALLOW_PORTS=()

usage() {
  cat <<'EOF'
Ubuntu 服务器管理脚本（SSH + UFW）

用法:
  ./server-admin.sh                # 进入交互菜单
  ./server-admin.sh --menu         # 进入交互菜单
  ./server-admin.sh --status       # 查看当前状态
  ./server-admin.sh --dry-run --status

非交互参数:
  --set-ssh-port <port>            设置 SSH 端口并放行 UFW
  --set-password-auth <yes|no>     设置 PasswordAuthentication
  --set-root-login <yes|no>        设置 PermitRootLogin
  --allow-port <port[/tcp|udp]>    放行防火墙端口，可重复指定
  --enable-ufw                     启用 UFW
  --dry-run                        仅打印命令，不执行写操作
  -h, --help                       显示帮助
EOF
}

log() {
  printf '[%s] %s\n' "${SCRIPT_NAME}" "$*"
}

err() {
  printf '[%s] ERROR: %s\n' "${SCRIPT_NAME}" "$*" >&2
}

warn() {
  printf '[%s] WARN: %s\n' "${SCRIPT_NAME}" "$*" >&2
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

run_cmd() {
  if [[ "${USE_DRY_RUN}" == "true" ]]; then
    log "DRY-RUN: $*"
    return 0
  fi
  "$@"
}

require_root_unless_dry_run() {
  if [[ "${USE_DRY_RUN}" == "true" ]]; then
    return 0
  fi
  if [[ "${EUID}" -ne 0 ]]; then
    err "该操作需要 root 权限，请使用 sudo 执行。"
    exit 1
  fi
}

validate_port() {
  local port="$1"
  if [[ ! "${port}" =~ ^[0-9]+$ ]]; then
    return 1
  fi
  if (( port < 1 || port > 65535 )); then
    return 1
  fi
  return 0
}

normalize_yes_no() {
  local raw="${1,,}"
  case "${raw}" in
    y|yes|true|1) printf 'yes' ;;
    n|no|false|0) printf 'no' ;;
    *) return 1 ;;
  esac
}

ensure_sshd_config_exists() {
  if [[ ! -f "${SSHD_CONFIG_PATH}" ]]; then
    err "未找到 SSH 配置文件: ${SSHD_CONFIG_PATH}"
    exit 1
  fi
}

backup_sshd_config_once() {
  if [[ -n "${SSHD_BACKUP_PATH}" ]]; then
    return 0
  fi
  ensure_sshd_config_exists
  SSHD_BACKUP_PATH="${SSHD_CONFIG_PATH}.bak.$(date +%Y%m%d%H%M%S)"
  run_cmd cp -a "${SSHD_CONFIG_PATH}" "${SSHD_BACKUP_PATH}"
  log "已备份 SSH 配置: ${SSHD_BACKUP_PATH}"
}

set_sshd_key() {
  local key="$1"
  local value="$2"
  ensure_sshd_config_exists

  if grep -Eq "^[[:space:]]*#?[[:space:]]*${key}[[:space:]]+" "${SSHD_CONFIG_PATH}"; then
    if [[ "${USE_DRY_RUN}" == "true" ]]; then
      log "DRY-RUN: 更新 ${SSHD_CONFIG_PATH} 中 ${key} => ${value}"
    else
      sed -i -E "s|^[[:space:]]*#?[[:space:]]*${key}[[:space:]].*$|${key} ${value}|g" "${SSHD_CONFIG_PATH}"
    fi
  else
    if [[ "${USE_DRY_RUN}" == "true" ]]; then
      log "DRY-RUN: 追加 ${key} ${value} 到 ${SSHD_CONFIG_PATH}"
    else
      printf '\n%s %s\n' "${key}" "${value}" >> "${SSHD_CONFIG_PATH}"
    fi
  fi
}

get_ssh_service_name() {
  if command_exists systemctl; then
    if systemctl list-unit-files --type=service 2>/dev/null | grep -q '^ssh\.service'; then
      printf 'ssh'
      return
    fi
    if systemctl list-unit-files --type=service 2>/dev/null | grep -q '^sshd\.service'; then
      printf 'sshd'
      return
    fi
  fi
  printf 'ssh'
}

verify_sshd_config() {
  if [[ "${USE_DRY_RUN}" == "true" ]]; then
    log "DRY-RUN: sshd -t -f ${SSHD_CONFIG_PATH}"
    return 0
  fi
  if ! command_exists sshd; then
    err "未找到 sshd 命令，无法校验配置。"
    return 1
  fi
  sshd -t -f "${SSHD_CONFIG_PATH}"
}

reload_ssh_service() {
  local service_name
  service_name="$(get_ssh_service_name)"
  if ! command_exists systemctl; then
    err "未找到 systemctl，无法重载 SSH 服务。"
    return 1
  fi
  run_cmd systemctl reload "${service_name}"
  log "已重载 SSH 服务: ${service_name}"
}

ensure_ufw_available() {
  if ! command_exists ufw; then
    err "未找到 ufw，请先安装：apt-get update && apt-get install -y ufw"
    exit 1
  fi
}

allow_ufw_port() {
  local input="$1"
  local port proto

  if [[ "${input}" == */* ]]; then
    port="${input%/*}"
    proto="${input#*/}"
  else
    port="${input}"
    proto="tcp"
  fi
  proto="${proto,,}"

  if ! validate_port "${port}"; then
    err "端口非法: ${port}"
    exit 1
  fi
  if [[ "${proto}" != "tcp" && "${proto}" != "udp" ]]; then
    err "协议非法: ${proto}（仅支持 tcp/udp）"
    exit 1
  fi

  ensure_ufw_available
  run_cmd ufw allow "${port}/${proto}"
  log "已放行端口: ${port}/${proto}"
}

enable_ufw_if_needed() {
  ensure_ufw_available
  run_cmd ufw --force enable
  log "UFW 已启用"
}

apply_ssh_port() {
  local new_port="$1"
  if ! validate_port "${new_port}"; then
    err "SSH 端口非法: ${new_port}"
    exit 1
  fi

  require_root_unless_dry_run
  backup_sshd_config_once

  # 先放行新端口，避免重载后无法连接。
  allow_ufw_port "${new_port}/tcp"
  set_sshd_key "Port" "${new_port}"

  if ! verify_sshd_config; then
    if [[ -n "${SSHD_BACKUP_PATH}" && "${USE_DRY_RUN}" != "true" ]]; then
      warn "检测失败，正在恢复备份配置: ${SSHD_BACKUP_PATH}"
      cp -a "${SSHD_BACKUP_PATH}" "${SSHD_CONFIG_PATH}"
    fi
    err "sshd 配置校验失败，已停止。"
    exit 1
  fi
  reload_ssh_service
}

apply_password_auth() {
  local normalized
  normalized="$(normalize_yes_no "$1")" || {
    err "PasswordAuthentication 仅支持 yes/no"
    exit 1
  }

  require_root_unless_dry_run
  backup_sshd_config_once
  set_sshd_key "PasswordAuthentication" "${normalized}"
  verify_sshd_config
  reload_ssh_service
}

apply_root_login() {
  local normalized
  normalized="$(normalize_yes_no "$1")" || {
    err "PermitRootLogin 仅支持 yes/no"
    exit 1
  }

  require_root_unless_dry_run
  backup_sshd_config_once
  set_sshd_key "PermitRootLogin" "${normalized}"
  verify_sshd_config
  reload_ssh_service
}

read_sshd_value() {
  local key="$1"
  local value
  value="$(grep -E "^[[:space:]]*${key}[[:space:]]+" "${SSHD_CONFIG_PATH}" 2>/dev/null | tail -n1 | awk '{print $2}')"
  if [[ -z "${value}" ]]; then
    printf '(未显式配置)'
  else
    printf '%s' "${value}"
  fi
}

show_status() {
  echo "当前 SSH 配置摘要"
  echo "  配置文件: ${SSHD_CONFIG_PATH}"
  if [[ -f "${SSHD_CONFIG_PATH}" ]]; then
    echo "  Port: $(read_sshd_value Port)"
    echo "  PasswordAuthentication: $(read_sshd_value PasswordAuthentication)"
    echo "  PermitRootLogin: $(read_sshd_value PermitRootLogin)"
  else
    echo "  SSH 配置文件不存在，无法读取当前值"
  fi

  echo
  echo "当前 UFW 状态"
  if command_exists ufw; then
    if [[ "${USE_DRY_RUN}" == "true" ]]; then
      log "DRY-RUN: ufw status"
    else
      ufw status || true
    fi
  else
    echo "  未安装 ufw"
  fi
}

show_menu() {
  cat <<'EOF'

================ Ubuntu 服务器管理菜单 ================
1) 配置 SSH 端口（自动放行 UFW）
2) 配置 SSH 密码登录（PasswordAuthentication）
3) 配置 SSH Root 登录（PermitRootLogin）
4) 防火墙放行端口（UFW）
5) 启用 UFW
6) 查看当前状态
0) 退出
======================================================
EOF
}

menu_loop() {
  local choice input

  # 进入菜单先回显当前配置，便于直接对照后续操作。
  show_status
  echo

  while true; do
    show_menu
    read -r -p "请输入数字选项: " choice
    case "${choice}" in
      1)
        read -r -p "请输入新的 SSH 端口: " input
        apply_ssh_port "${input}"
        ;;
      2)
        read -r -p "请输入 yes/no: " input
        apply_password_auth "${input}"
        ;;
      3)
        read -r -p "请输入 yes/no: " input
        apply_root_login "${input}"
        ;;
      4)
        read -r -p "请输入端口（如 8080 或 53/udp）: " input
        allow_ufw_port "${input}"
        ;;
      5)
        require_root_unless_dry_run
        enable_ufw_if_needed
        ;;
      6)
        show_status
        ;;
      0)
        log "已退出。"
        break
        ;;
      *)
        warn "无效选项: ${choice}"
        ;;
    esac
    echo
  done
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --menu)
        ACTION_MENU="true"
        shift
        ;;
      --status)
        ACTION_STATUS="true"
        shift
        ;;
      --dry-run)
        USE_DRY_RUN="true"
        shift
        ;;
      --enable-ufw)
        ENABLE_UFW="true"
        shift
        ;;
      --set-ssh-port)
        [[ $# -ge 2 ]] || { err "--set-ssh-port 缺少参数"; exit 1; }
        SET_SSH_PORT="$2"
        shift 2
        ;;
      --set-password-auth)
        [[ $# -ge 2 ]] || { err "--set-password-auth 缺少参数"; exit 1; }
        SET_PASSWORD_AUTH="$2"
        shift 2
        ;;
      --set-root-login)
        [[ $# -ge 2 ]] || { err "--set-root-login 缺少参数"; exit 1; }
        SET_ROOT_LOGIN="$2"
        shift 2
        ;;
      --allow-port)
        [[ $# -ge 2 ]] || { err "--allow-port 缺少参数"; exit 1; }
        ALLOW_PORTS+=("$2")
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        err "未知参数: $1"
        usage
        exit 1
        ;;
    esac
  done
}

run_non_interactive_actions() {
  local has_action="false"

  if [[ -n "${SET_SSH_PORT}" ]]; then
    apply_ssh_port "${SET_SSH_PORT}"
    has_action="true"
  fi
  if [[ -n "${SET_PASSWORD_AUTH}" ]]; then
    apply_password_auth "${SET_PASSWORD_AUTH}"
    has_action="true"
  fi
  if [[ -n "${SET_ROOT_LOGIN}" ]]; then
    apply_root_login "${SET_ROOT_LOGIN}"
    has_action="true"
  fi
  if [[ "${#ALLOW_PORTS[@]}" -gt 0 ]]; then
    local p
    require_root_unless_dry_run
    for p in "${ALLOW_PORTS[@]}"; do
      allow_ufw_port "${p}"
    done
    has_action="true"
  fi
  if [[ "${ENABLE_UFW}" == "true" ]]; then
    require_root_unless_dry_run
    enable_ufw_if_needed
    has_action="true"
  fi
  if [[ "${ACTION_STATUS}" == "true" ]]; then
    show_status
    has_action="true"
  fi

  if [[ "${has_action}" == "false" ]]; then
    menu_loop
  fi
}

main() {
  parse_args "$@"

  if [[ "${ACTION_MENU}" == "true" ]]; then
    menu_loop
    exit 0
  fi

  run_non_interactive_actions
}

main "$@"
