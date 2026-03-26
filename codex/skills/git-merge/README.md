# git-merge skill

用于筛选 `develop` 分支中指定提交人的历史提交，生成 `git-merge.md` 审核日志，并在确认后把改动写入 `master`（或其他目标分支）。

## 文件说明

- `SKILL.md`：技能使用规范
- `scripts/git_merge.sh`：执行脚本

## 快速开始

### 1) 生成汇总（prepare）

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

### 2) 用户确认后写入目标分支（apply）

```bash
bash ~/.codex/skills/git-merge/scripts/git_merge.sh apply \
  --plan-file .git-merge-plan.env \
  --confirm yes
```

## 参数

### prepare

- `--source <branch>`：源分支，默认 `develop`
- `--target <branch>`：目标分支，默认 `master`
- `--author <pattern>`：提交人过滤（必填）
- `--since <date>`：起始时间（可选，建议）
- `--until <date>`：结束时间（可选）
- `--max-count <N>`：最多提交数（可选）
- `--output <path>`：日志路径，默认 `git-merge.md`
- `--plan-file <path>`：计划文件，默认 `.git-merge-plan.env`

> `--since` 与 `--max-count` 至少提供一个，用于明确“提交历史范围”。

### apply

- `--plan-file <path>`：prepare 阶段生成的计划文件
- `--confirm yes`：确认执行（必填，固定值 `yes`）

## 输出

- `git-merge.md`：
  - 分支信息和筛选条件
  - 命中提交列表
  - 每个提交的修改文件
  - 文件增删统计
  - 关键 diff 片段
  - apply 执行结果
- `.git-merge-plan.env`：
  - 机器可读计划，用于 apply 阶段

