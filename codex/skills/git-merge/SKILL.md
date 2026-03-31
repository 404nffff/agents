---
name: git-merge
description: 在 develop_dir 中按 git log 与作者筛选提交，生成改动计划，用户确认后自动把改动写入 master_dir。
---

# Git Merge

脚本目录：`~/.codex/skills/git-merge/`

本 skill 使用两阶段流程：

1. `prepare`：在 `develop_dir` 按分支范围、作者和时间条件筛选 git 提交，生成改动计划报告。
2. `apply`：在用户确认无误后，把计划内改动自动写入 `master_dir`。

## 必填输入

1. `--develop-dir`：开发仓库目录（源）
2. `--master-dir`：目标目录（写入目录）
3. `--author`：提交人筛选（姓名、邮箱或关键字）
4. 提交历史筛选（至少一个）：
   - `--since <date>`（建议）
   - `--max-count <N>`

## 第一步：生成汇总日志

```bash
bash ~/.codex/skills/git-merge/scripts/git_merge.sh prepare \
  --develop-dir /path/to/develop_dir \
  --master-dir /path/to/master_dir \
  --source develop \
  --target master \
  --author "alice@example.com" \
  --since "2026-03-01" \
  --until "2026-03-25" \
  --output git-merge.md \
  --plan-file .git-merge-plan.env
```

执行后会生成：

1. `git-merge.md`：提交摘要 + 修改计划（新增/修改/删除文件清单）
2. `.git-merge-plan.env`：后续 apply 使用的执行计划
3. `.git-merge-plan.env.added/.modified/.deleted`：机器可读文件清单

## 第二步：用户确认后执行写入

只有在用户明确确认后，才允许执行：

```bash
bash ~/.codex/skills/git-merge/scripts/git_merge.sh apply \
  --plan-file .git-merge-plan.env \
  --confirm yes
```

该步骤会：

1. 严格校验 `--confirm yes`
2. 按计划从 `develop_dir` 的 `source` 分支导出文件并写入 `master_dir`
3. 按计划删除 `master_dir` 中多余文件
4. 在 `git-merge.md` 追加执行结果

## 失败处理

如果 apply 阶段遇到路径缺失或文件写入失败，脚本会中断并提示：

1. 修复目录或权限问题后重新执行 `prepare`
2. 再次确认计划后执行 `apply --confirm yes`
