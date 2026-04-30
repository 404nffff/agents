# git-merge skill

用于在 `develop_dir` 中按 `git log` 条件筛选提交，生成 `git-merge.md` 修改计划，并在确认后把改动自动写入 `master_dir`。

## 文件说明

- `SKILL.md`：技能使用规范
- `scripts/git_merge.sh`：执行脚本

## 快速开始

### 1) 生成汇总（prepare）

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

### 2) 用户确认后写入目标分支（apply）

```bash
bash ~/.codex/skills/git-merge/scripts/git_merge.sh apply \
  --plan-file .git-merge-plan.env \
  --confirm yes
```

## 参数

### prepare

- `--develop-dir <path>`：源目录（必填）
- `--master-dir <path>`：目标目录（必填）
- `--source <branch>`：源分支（默认 `develop`）
- `--target <branch>`：基线分支（默认 `master`）
- `--author <pattern>`：提交人筛选（必填）
- `--since <date>`：起始时间（可选，建议）
- `--until <date>`：结束时间（可选）
- `--max-count <N>`：最多提交数（可选）
- `--output <path>`：日志路径，默认 `git-merge.md`
- `--plan-file <path>`：计划文件，默认 `.git-merge-plan.env`

> `--since` 与 `--max-count` 至少提供一个，用于限定提交历史范围。

### apply

- `--plan-file <path>`：prepare 阶段生成的计划文件
- `--confirm yes`：确认执行（必填，固定值 `yes`）

## 输出

- `git-merge.md`：
  - git 提交筛选条件与命中提交摘要
  - 修改计划（新增/修改/删除）
  - apply 执行结果
- `.git-merge-plan.env`：
  - 机器可读计划，用于 apply 阶段（含目录、分支、筛选条件与列表文件路径）
- `.git-merge-plan.env.added/.modified/.deleted`：
  - 文件级变更清单，用于 apply 阶段自动写入
