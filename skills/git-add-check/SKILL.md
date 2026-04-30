---
name: git-add-check
description: 检查已暂存（git add）的代码是否存在语法错误，输出汇总报告并以退出码表示是否通过。
---

# Git Add Check

脚本目录：`~/.codex/skills/git-add-check/`

本 skill 仅检查 **暂存区（staged）** 的文件内容，避免被未暂存改动干扰。

## 用途

在 `git commit` 之前执行，快速发现已暂存代码中的语法错误。

## 执行命令

```bash
bash ~/.codex/skills/git-add-check/scripts/git_add_check.sh
```

## 常用参数

1. `--verbose`：打印每个文件的检查明细
2. `--strict`：遇到不支持的文件类型也视为失败
3. `--staged-only`：显式声明只检查暂存区（默认已启用，保留该参数用于可读性）

示例：

```bash
bash ~/.codex/skills/git-add-check/scripts/git_add_check.sh --verbose
```

```bash
bash ~/.codex/skills/git-add-check/scripts/git_add_check.sh --strict
```

## 支持的语法检查器

1. Shell：`bash -n`
2. Python：`python3 -m py_compile`
3. JavaScript：`node --check`
4. TypeScript：`node --check`（仅做 JS 语法层快速检查，非完整类型检查）
5. Go：`gofmt -e`
6. PHP：`php -l`
7. Ruby：`ruby -c`

> 若环境中缺少某检查器，脚本会标记为 `SKIP`；`--strict` 模式下会记为失败。

