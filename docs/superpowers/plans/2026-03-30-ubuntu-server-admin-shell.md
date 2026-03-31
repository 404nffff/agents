# Ubuntu Server Admin Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 提供一个 Ubuntu 轻量化交互式 Shell 脚本，进入数字菜单后可配置 SSH 与 UFW 端口放行。

**Architecture:** 单文件 Bash 脚本实现菜单循环与操作函数。通过幂等方式修改 `sshd_config`，并使用 `ufw allow` 放行端口；提供 `--help`、`--status`、`--dry-run` 便于验证与演练。

**Tech Stack:** Bash、sed、grep、awk、cp、systemctl、ufw、sshd

---

### Task 1: 先写失败测试（RED）

**Files:**
- Create: `shell/test_server_admin.sh`
- Test: `shell/test_server_admin.sh`

- [ ] **Step 1: 写一个会失败的测试**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/server-admin.sh"

if [[ ! -x "$SCRIPT_PATH" ]]; then
  echo "FAIL: 脚本不存在或不可执行: $SCRIPT_PATH" >&2
  exit 1
fi
```

- [ ] **Step 2: 运行测试并确认失败**

Run: `bash shell/test_server_admin.sh`  
Expected: FAIL，提示脚本不存在或不可执行

### Task 2: 实现菜单脚本（GREEN）

**Files:**
- Create: `shell/server-admin.sh`
- Modify: `shell/test_server_admin.sh`
- Test: `shell/test_server_admin.sh`

- [ ] **Step 1: 实现最小可用脚本**

```bash
#!/usr/bin/env bash
set -euo pipefail

show_main_menu() {
  echo "1) 配置 SSH 端口"
  echo "2) 配置 SSH 密码登录"
  echo "3) 配置 SSH Root 登录"
  echo "4) 放行防火墙端口"
  echo "5) 查看当前状态"
  echo "0) 退出"
}
```

- [ ] **Step 2: 扩展为完整功能**

```bash
# 增加：参数解析、sshd_config 幂等更新、ufw 放行、状态查看、dry-run。
```

- [ ] **Step 3: 运行测试并确认通过**

Run: `bash shell/test_server_admin.sh`  
Expected: PASS

### Task 3: 语法与行为验证（REFACTOR/VERIFY）

**Files:**
- Modify: `shell/server-admin.sh`
- Test: `shell/test_server_admin.sh`

- [ ] **Step 1: 语法检查**

Run: `bash -n shell/server-admin.sh`  
Expected: 无输出，退出码 0

- [ ] **Step 2: 非交互验证**

Run: `bash shell/server-admin.sh --help`  
Expected: 输出中文帮助和菜单入口说明

- [ ] **Step 3: 状态查看验证**

Run: `bash shell/server-admin.sh --status --dry-run`  
Expected: 输出 SSH/UFW 状态信息，不执行系统修改

