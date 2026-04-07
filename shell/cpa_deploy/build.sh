#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER_URL="https://raw.githubusercontent.com/brokechubb/cliproxyapi-installer/refs/heads/master/cliproxyapi-installer"
PORT="3317"
ALLOW_REMOTE="true"
SECRET_KEY=""
USAGE_STATISTICS_ENABLED="true"
INSTALL_FIREWALL="true"
INSTALL_FAIL2BAN="true"
DRY_RUN="false"
GENERATED_API_KEY=""
FAIL2BAN_JAIL_PATH="/etc/fail2ban/jail.d/cpa-sshd.local"

TARGET_USER=""
TARGET_GROUP=""
TARGET_HOME=""
CLIPROXYAPI_DIR=""
CONFIG_PATH=""

usage() {
  cat <<EOF
用法:
  ./${SCRIPT_NAME} install [选项]
  ./${SCRIPT_NAME} deploy [选项]
  ./${SCRIPT_NAME} uninstall [选项]
  ./${SCRIPT_NAME} status
  ./${SCRIPT_NAME} fw list
  ./${SCRIPT_NAME} fw add
  ./${SCRIPT_NAME} fw del

说明:
  按 shell/plan.md 自动执行 cliproxyapi 部署:
  1) 安装 curl
  2) 安装 cliproxyapi
  3) 修改 ~/cliproxyapi/config.yaml
  4) 复制 shell/cpa_deploy/config/*.json 到 ~/.cli-proxy-api/
  5) 启动 cliproxyapi.service (systemctl --user)
  6) 安装并配置 ufw (开放 22/tcp，3317 全放行)
  7) 安装并启动 fail2ban

选项:
  --port <port>             覆盖配置端口，默认 3317
  --secret-key <key>        覆盖 remote-management.secret-key
  --skip-firewall           跳过防火墙安装与配置
  --skip-fail2ban           跳过 fail2ban 安装
  --dry-run                 仅打印命令，不落盘
  -h, --help                显示帮助

防火墙子命令:
  fw list                   查看 3317/tcp 规则
  fw add                    新增 3317/tcp 全放行规则
  fw del                    删除 3317/tcp 全放行规则

兼容说明:
  install                   等价于 deploy
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

run_shell() {
  local cmd="$1"
  if [[ "${DRY_RUN}" == "true" ]]; then
    log "DRY-RUN: bash -lc ${cmd}"
    return 0
  fi
  bash -lc "${cmd}"
}

run_as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    run_cmd "$@"
  else
    run_cmd sudo "$@"
  fi
}

run_shell_as_target_user() {
  local cmd="$1"
  if [[ "$(id -un)" == "${TARGET_USER}" ]]; then
    run_shell "${cmd}"
  else
    if [[ "${DRY_RUN}" == "true" ]]; then
      log "DRY-RUN: sudo -iu ${TARGET_USER} bash -lc ${cmd}"
      return 0
    fi
    sudo -iu "${TARGET_USER}" bash -lc "${cmd}"
  fi
}

validate_port() {
  local value="$1"
  [[ "${value}" =~ ^[0-9]+$ ]] || return 1
  (( value >= 1 && value <= 65535 ))
}

generate_strong_api_key() {
  local candidate=""
  if command_exists openssl; then
    while true; do
      candidate="$(openssl rand -base64 64 2>/dev/null | tr -d '\n' | tr '+/' '-_' | tr -dc 'A-Za-z0-9_-')"
      [[ "${#candidate}" -ge 48 ]] && break
    done
  else
    while true; do
      candidate="$(head -c 96 /dev/urandom | base64 | tr -d '\n' | tr '+/' '-_' | tr -dc 'A-Za-z0-9_-')"
      [[ "${#candidate}" -ge 48 ]] && break
    done
  fi
  GENERATED_API_KEY="${candidate:0:48}"
}

generate_strong_secret_key() {
  local candidate=""
  if [[ -n "${SECRET_KEY}" ]]; then
    return 0
  fi
  if command_exists openssl; then
    while true; do
      candidate="$(openssl rand -base64 96 2>/dev/null | tr -d '\n' | tr '+/' '-_' | tr -dc 'A-Za-z0-9_-')"
      [[ "${#candidate}" -ge 64 ]] && break
    done
  else
    while true; do
      candidate="$(head -c 128 /dev/urandom | base64 | tr -d '\n' | tr '+/' '-_' | tr -dc 'A-Za-z0-9_-')"
      [[ "${#candidate}" -ge 64 ]] && break
    done
  fi
  SECRET_KEY="${candidate:0:64}"
}

resolve_target_user() {
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    TARGET_USER="${SUDO_USER}"
  else
    TARGET_USER="$(id -un)"
  fi
  TARGET_GROUP="$(id -gn "${TARGET_USER}")"
  TARGET_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
  [[ -n "${TARGET_HOME}" ]] || die "无法解析目标用户家目录: ${TARGET_USER}"

  CLIPROXYAPI_DIR="${TARGET_HOME}/cliproxyapi"
  CONFIG_PATH="${CLIPROXYAPI_DIR}/config.yaml"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --port)
        [[ $# -ge 2 ]] || die "--port 缺少参数"
        PORT="$2"
        shift 2
        ;;
      --secret-key)
        [[ $# -ge 2 ]] || die "--secret-key 缺少参数"
        SECRET_KEY="$2"
        shift 2
        ;;
      --skip-firewall)
        INSTALL_FIREWALL="false"
        shift
        ;;
      --skip-fail2ban)
        INSTALL_FAIL2BAN="false"
        shift
        ;;
      --dry-run)
        DRY_RUN="true"
        shift
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
  command_exists bash || die "未找到 bash"
  command_exists apt-get || die "仅支持 apt-get 环境"
  command_exists systemctl || die "未找到 systemctl"
  validate_port "${PORT}" || die "端口非法: ${PORT}"
  [[ "${ALLOW_REMOTE}" == "true" || "${ALLOW_REMOTE}" == "false" ]] || die "ALLOW_REMOTE 仅支持 true/false"
}

install_system_packages() {
  local -a missing_packages=()

  if ! command_exists curl; then
    missing_packages+=("curl")
  fi
  if [[ "${INSTALL_FIREWALL}" == "true" ]] && ! command_exists ufw; then
    missing_packages+=("ufw")
  fi
  if [[ "${INSTALL_FAIL2BAN}" == "true" ]] && ! command_exists fail2ban-client; then
    missing_packages+=("fail2ban")
  fi

  if [[ "${#missing_packages[@]}" -eq 0 ]]; then
    log "步骤 1/7: 依赖已安装，跳过 apt 安装。"
    return 0
  fi

  log "步骤 1/7: 安装缺失依赖 (${missing_packages[*]})"
  run_as_root apt-get update
  run_as_root apt-get install -y "${missing_packages[@]}"
}

install_cliproxyapi() {
  local installer_file
  if [[ -d "${CLIPROXYAPI_DIR}" ]]; then
    log "步骤 2/7: 检测到已安装目录 ${CLIPROXYAPI_DIR}，跳过安装。"
    return 0
  fi

  installer_file="$(mktemp)"

  log "步骤 2/7: 安装 cliproxyapi"
  run_cmd curl -fsSL "${INSTALLER_URL}" -o "${installer_file}"
  run_cmd chmod 644 "${installer_file}"
  run_shell_as_target_user "bash '${installer_file}'"
  run_cmd rm -f "${installer_file}"

  [[ "${DRY_RUN}" == "true" || -d "${CLIPROXYAPI_DIR}" ]] || die "安装后未找到目录: ${CLIPROXYAPI_DIR}"
}

rewrite_config() {
  local tmp_file cleaned_file
  tmp_file="$(mktemp)"
  cleaned_file="$(mktemp)"

  if [[ "${DRY_RUN}" != "true" && ! -f "${CONFIG_PATH}" ]]; then
    die "未找到配置文件: ${CONFIG_PATH}"
  fi

  log "步骤 3/7: 修改配置 ${CONFIG_PATH}"
  if [[ "${DRY_RUN}" == "true" ]]; then
    log "DRY-RUN: 将 port 更新为 ${PORT}"
    log "DRY-RUN: 将 usage-statistics-enabled 更新为 ${USAGE_STATISTICS_ENABLED}"
    log "DRY-RUN: 将 api-keys 默认值替换为自动生成强密码"
    log "DRY-RUN: 将 remote-management.allow-remote 更新为 ${ALLOW_REMOTE}"
    log "DRY-RUN: 将 remote-management.secret-key 更新为 ${SECRET_KEY}"
    rm -f "${tmp_file}" "${cleaned_file}"
    return 0
  fi

  [[ -n "${GENERATED_API_KEY}" ]] || die "未生成 api-keys 强密码。"
  [[ -n "${SECRET_KEY}" ]] || die "未生成 remote-management.secret-key。"
  cp "${CONFIG_PATH}" "${tmp_file}"

  if grep -Eq '^[[:space:]]*port:[[:space:]]*[0-9]+' "${tmp_file}"; then
    sed -E -i "0,/^[[:space:]]*port:[[:space:]]*[0-9]+/s//port: ${PORT}/" "${tmp_file}"
  else
    {
      printf 'port: %s\n' "${PORT}"
      cat "${tmp_file}"
    } > "${cleaned_file}"
    mv "${cleaned_file}" "${tmp_file}"
  fi

  if grep -Eq '^[[:space:]]*usage-statistics-enabled:[[:space:]]*(true|false)' "${tmp_file}"; then
    sed -E -i "0,/^[[:space:]]*usage-statistics-enabled:[[:space:]]*(true|false)/s//usage-statistics-enabled: ${USAGE_STATISTICS_ENABLED}/" "${tmp_file}"
  else
    sed -E -i "0,/^[[:space:]]*port:[[:space:]]*[0-9]+/s//&\\nusage-statistics-enabled: ${USAGE_STATISTICS_ENABLED}/" "${tmp_file}"
  fi

  awk -v allow_remote="${ALLOW_REMOTE}" -v secret_key="${SECRET_KEY}" -v api_key="${GENERATED_API_KEY}" '
    BEGIN {in_block=""; replaced_remote=0; replaced_api=0}
    function print_remote_block() {
      print "remote-management:"
      print "  allow-remote: " allow_remote
      print "  secret-key: \"" secret_key "\""
    }
    function print_api_keys_block() {
      print "api-keys:"
      print "  - \"" api_key "\""
    }
    {
      if ($0 ~ /^[[:space:]]*remote-management:[[:space:]]*$/) {
        if (replaced_remote == 0) {
          print_remote_block()
          replaced_remote=1
        }
        in_block="remote-management"
        next
      }
      if ($0 ~ /^[[:space:]]*api-keys:[[:space:]]*$/) {
        if (replaced_api == 0) {
          print_api_keys_block()
          replaced_api=1
        }
        in_block="api-keys"
        next
      }

      if (in_block != "") {
        if ($0 ~ /^[[:space:]]+/ || $0 ~ /^[[:space:]]*$/) {
          next
        }
        in_block=""
      }

      print
    }
    END {
      if (replaced_api == 0) {
        if (NR > 0) {
          print ""
        }
        print_api_keys_block()
      }
      if (replaced_remote == 0) {
        print ""
        print_remote_block()
      }
    }
  ' "${tmp_file}" > "${cleaned_file}"

  if [[ "$(id -u)" -eq 0 ]]; then
    run_cmd install -m 644 -o "${TARGET_USER}" -g "${TARGET_GROUP}" "${cleaned_file}" "${CONFIG_PATH}"
  else
    run_cmd install -m 644 "${cleaned_file}" "${CONFIG_PATH}"
  fi

  rm -f "${tmp_file}" "${cleaned_file}"
}

copy_json_configs() {
  local source_dir target_dir file_name file_path
  local -a json_files=()

  source_dir="${SCRIPT_DIR}/config"
  target_dir="${TARGET_HOME}/.cli-proxy-api"

  if [[ ! -d "${source_dir}" ]]; then
    warn "未找到 JSON 配置目录，跳过复制: ${source_dir}"
    return 0
  fi

  shopt -s nullglob
  json_files=("${source_dir}"/*.json)
  shopt -u nullglob

  if [[ "${#json_files[@]}" -eq 0 ]]; then
    warn "目录 ${source_dir} 下未找到 JSON 配置，跳过复制。"
    return 0
  fi

  log "步骤 4/7: 复制 JSON 配置到 ${target_dir}"
  if [[ "$(id -u)" -eq 0 ]]; then
    run_as_root install -d -m 755 -o "${TARGET_USER}" -g "${TARGET_GROUP}" "${target_dir}"
  else
    run_cmd install -d -m 755 "${target_dir}"
  fi

  for file_path in "${json_files[@]}"; do
    file_name="$(basename "${file_path}")"
    if [[ "$(id -u)" -eq 0 ]]; then
      run_as_root install -m 644 -o "${TARGET_USER}" -g "${TARGET_GROUP}" "${file_path}" "${target_dir}/${file_name}"
    else
      run_cmd install -m 644 "${file_path}" "${target_dir}/${file_name}"
    fi
  done

  log "已复制 ${#json_files[@]} 个 JSON 配置文件。"
}

start_service() {
  log "步骤 5/7: 启动 cliproxyapi.service"
  run_shell_as_target_user "cd '${CLIPROXYAPI_DIR}' && systemctl --user enable cliproxyapi.service"
  run_shell_as_target_user "systemctl --user restart cliproxyapi.service"
  run_shell_as_target_user "systemctl --user --no-pager status cliproxyapi.service"
}

configure_firewall() {
  [[ "${INSTALL_FIREWALL}" == "true" ]] || return 0

  log "步骤 6/7: 配置防火墙"
  run_as_root ufw --force enable
  run_as_root ufw allow 22/tcp
  run_as_root ufw allow "${PORT}/tcp"

  run_as_root ufw status verbose
}

fw_list_rules() {
  local status_output
  command_exists ufw || die "未找到 ufw，请先执行部署流程安装。"

  if [[ "$(id -u)" -eq 0 ]]; then
    status_output="$(ufw status numbered 2>&1)" || die "读取 ufw 规则失败: ${status_output}"
  else
    status_output="$(sudo ufw status numbered 2>&1)" || die "读取 ufw 规则失败: ${status_output}"
  fi

  printf '%s\n' "${status_output}"
}

fw_add_rule() {
  command_exists ufw || die "未找到 ufw，请先执行部署流程安装。"
  run_as_root ufw allow 3317/tcp
  fw_list_rules
}

fw_del_rule() {
  command_exists ufw || die "未找到 ufw，请先执行部署流程安装。"
  run_as_root ufw --force delete allow 3317/tcp
  fw_list_rules
}

handle_fw_command() {
  local action="${1:-}"
  shift || true
  [[ "$#" -eq 0 ]] || die "fw 子命令不支持额外参数。"

  case "${action}" in
    list)
      fw_list_rules
      ;;
    add)
      fw_add_rule
      ;;
    del|delete|rm)
      fw_del_rule
      ;;
    *)
      die "未知 fw 子命令: ${action:-<empty>}，可用: list/add/del"
      ;;
  esac
}

show_cliproxyapi_status() {
  echo "===== cliproxyapi.service (user: ${TARGET_USER}) ====="
  echo "目录: ${CLIPROXYAPI_DIR}"
  if [[ ! -d "${CLIPROXYAPI_DIR}" ]]; then
    warn "cliproxyapi 目录不存在。"
  fi
  if ! command_exists systemctl; then
    warn "未找到 systemctl，无法查询 cliproxyapi 服务状态。"
    return 0
  fi
  if ! run_shell_as_target_user "systemctl --user --no-pager status cliproxyapi.service"; then
    warn "读取 cliproxyapi.service 状态失败。"
  fi
}

show_fail2ban_status() {
  echo "===== fail2ban ====="
  if ! command_exists systemctl; then
    warn "未找到 systemctl，无法查询 fail2ban 状态。"
    return 0
  fi
  if ! run_as_root systemctl --no-pager status fail2ban; then
    warn "读取 fail2ban 状态失败。"
  fi
  echo "===== fail2ban jail file ====="
  echo "jail_file: ${FAIL2BAN_JAIL_PATH}"
  if [[ -f "${FAIL2BAN_JAIL_PATH}" ]]; then
    if ! run_as_root cat "${FAIL2BAN_JAIL_PATH}"; then
      warn "读取 fail2ban jail 文件失败。"
    fi
  else
    warn "未找到 fail2ban jail 文件。"
  fi
  echo "===== fail2ban sshd jail ====="
  if ! command_exists fail2ban-client; then
    warn "未找到 fail2ban-client，无法查询 sshd jail 状态。"
    return 0
  fi
  if ! run_as_root fail2ban-client status sshd; then
    warn "读取 fail2ban sshd jail 状态失败。"
  fi
}

show_ufw_status() {
  echo "===== ufw ====="
  if ! command_exists ufw; then
    warn "未找到 ufw。"
    return 0
  fi
  if ! run_as_root ufw status verbose; then
    warn "读取 ufw 状态失败。"
  fi
}

show_services_status() {
  echo "===== deploy context ====="
  echo "target_user: ${TARGET_USER}"
  echo "target_home: ${TARGET_HOME}"
  echo "deploy_dir : ${CLIPROXYAPI_DIR}"
  echo "config_file: ${CONFIG_PATH}"
  show_cliproxyapi_status
  show_fail2ban_status
  show_ufw_status
}

remove_3317_firewall_rules() {
  local status_output rule_numbers rule_no

  if ! command_exists ufw; then
    warn "未找到 ufw，跳过 3317 规则清理。"
    return 0
  fi

  if [[ "$(id -u)" -eq 0 ]]; then
    status_output="$(ufw status numbered 2>/dev/null || true)"
  else
    status_output="$(sudo ufw status numbered 2>/dev/null || true)"
  fi

  rule_numbers="$(printf '%s\n' "${status_output}" | sed -n '/3317\/tcp/s/^[[:space:]]*\[\([0-9][0-9]*\)\].*/\1/p' | sort -rn)"
  if [[ -z "${rule_numbers}" ]]; then
    log "未发现 3317/tcp 规则，无需清理。"
    return 0
  fi

  for rule_no in ${rule_numbers}; do
    if ! run_as_root ufw --force delete "${rule_no}"; then
      warn "删除 ufw 规则失败，编号: ${rule_no}"
    fi
  done
}

uninstall_cliproxyapi() {
  local unit_file
  log "开始卸载 cliproxyapi 相关组件"

  if command_exists systemctl; then
    if ! run_shell_as_target_user "systemctl --user stop cliproxyapi.service || true"; then
      warn "停止 cliproxyapi.service 失败。"
    fi
    if ! run_shell_as_target_user "systemctl --user disable cliproxyapi.service || true"; then
      warn "禁用 cliproxyapi.service 失败。"
    fi
  else
    warn "未找到 systemctl，跳过服务停用。"
  fi

  for unit_file in \
    "${TARGET_HOME}/.config/systemd/user/cliproxyapi.service" \
    "${TARGET_HOME}/.local/share/systemd/user/cliproxyapi.service"; do
    if [[ -f "${unit_file}" ]]; then
      run_cmd rm -f "${unit_file}"
    fi
  done

  if command_exists systemctl; then
    run_shell_as_target_user "systemctl --user daemon-reload || true"
  fi

  if [[ -d "${CLIPROXYAPI_DIR}" ]]; then
    [[ -n "${CLIPROXYAPI_DIR}" && "${CLIPROXYAPI_DIR}" != "/" ]] || die "卸载路径异常，拒绝删除: ${CLIPROXYAPI_DIR}"
    run_cmd rm -rf "${CLIPROXYAPI_DIR}"
    log "已删除目录: ${CLIPROXYAPI_DIR}"
  else
    log "目录不存在，跳过删除: ${CLIPROXYAPI_DIR}"
  fi

  remove_3317_firewall_rules
  log "卸载完成。"
}

configure_fail2ban() {
  [[ "${INSTALL_FAIL2BAN}" == "true" ]] || return 0
  log "步骤 7/7: 安装并启用 fail2ban"
  configure_fail2ban_jail
  run_as_root systemctl enable fail2ban
  run_as_root systemctl restart fail2ban
  run_as_root systemctl --no-pager status fail2ban
}

configure_fail2ban_jail() {
  local tmp_file
  tmp_file="$(mktemp)"

  if [[ "${DRY_RUN}" == "true" ]]; then
    log "DRY-RUN: 写入 fail2ban 默认规则 ${FAIL2BAN_JAIL_PATH}"
    log "DRY-RUN: 规则仅启用 sshd，监听 22 端口，bantime=1h，findtime=10m，maxretry=5"
    rm -f "${tmp_file}"
    return 0
  fi

  cat > "${tmp_file}" <<'EOF'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port = 22
backend = systemd
EOF

  run_as_root install -d -m 755 /etc/fail2ban/jail.d
  run_as_root install -m 644 "${tmp_file}" "${FAIL2BAN_JAIL_PATH}"
  rm -f "${tmp_file}"
}

main() {
  local action="${1:-}"

  case "${action}" in
    "")
      usage
      die "请先输入参数：install/deploy/uninstall/status/fw"
      ;;
    -h|--help|help)
      usage
      return 0
      ;;
    fw)
      shift
      handle_fw_command "$@"
      return 0
      ;;
    status)
      shift
      [[ "$#" -eq 0 ]] || die "status 不支持额外参数。"
      resolve_target_user
      show_services_status
      return 0
      ;;
    install|deploy)
      shift
      parse_args "$@"
      resolve_target_user
      ensure_requirements
      generate_strong_secret_key
      generate_strong_api_key

      log "目标用户: ${TARGET_USER} (${TARGET_HOME})"
      log "部署目录: ${CLIPROXYAPI_DIR}"
      log "配置文件: ${CONFIG_PATH}"

      install_system_packages
      install_cliproxyapi
      rewrite_config
      copy_json_configs
      start_service
      configure_firewall
      configure_fail2ban

      log "部署完成。"
      log "remote-management.secret-key: ${SECRET_KEY}"
      log "api-keys: ${GENERATED_API_KEY}"
      ;;
    uninstall)
      shift
      parse_args "$@"
      resolve_target_user
      uninstall_cliproxyapi
      ;;
    *)
      usage
      die "未知参数: ${action}，请使用 install/deploy/uninstall/status/fw"
      ;;
  esac
}

main "$@"
