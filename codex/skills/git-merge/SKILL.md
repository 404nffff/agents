---
name: git-merge
description: 对比两个分支（默认 develop/master），按提交人和提交历史筛选 develop 提交，生成 git-merge.md 汇总；用户确认后自动写入目标分支。
---

# Git Merge

脚本目录：`~/.codex/skills/git-merge/`

本 skill 使用两阶段流程：

1. `prepare`：筛选提交并生成 `git-merge.md` 汇总日志。
2. `apply`：在用户确认无误后，把筛选后的提交写入目标分支（默认 `master`）。

## 必填输入

1. `--source`：源分支（通常是 `develop`）
2. `--target`：目标分支（通常是 `master`）
3. `--author`：提交人（姓名、邮箱或正则关键字）
4. 提交历史筛选（至少一个）：
   - `--since <date>`（建议）
   - `--max-count <N>`

## 第一步：生成汇总日志

```bash
bash ~/.codex/skills/git-merge/scripts/git_merge.sh prepare \
  --source develop \
  --target master \
  --author "alice@example.com" \
  --since "2026-03-01" \
  --until "2026-03-25" \
  --output git-merge.md \
  --plan-file .git-merge-plan.env
```

执行后会生成：

1. `git-merge.md`：提交摘要、修改文件、增删统计、关键 diff 片段
2. `.git-merge-plan.env`：后续 apply 使用的执行计划

## 第二步：用户确认后执行写入

只有在用户明确确认后，才允许执行：

```bash
bash ~/.codex/skills/git-merge/scripts/git_merge.sh apply \
  --plan-file .git-merge-plan.env \
  --confirm yes
```

该步骤会：

1. 检查工作区是否干净
2. 自动切换到目标分支
3. 按计划顺序逐个 `cherry-pick` 到目标分支
4. 在 `git-merge.md` 追加执行结果

## 失败处理

如果 `cherry-pick` 冲突，脚本会中断并提示：

1. 手动解决冲突后执行 `git cherry-pick --continue`
2. 或执行 `git cherry-pick --abort` 后重新规划

