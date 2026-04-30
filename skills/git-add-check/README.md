# git-add-check skill

检测已 `git add` 到暂存区的代码是否有语法错误。

## 文件结构

- `SKILL.md`：技能说明
- `scripts/git_add_check.sh`：检查脚本

## 快速开始

```bash
bash ~/.codex/skills/git-add-check/scripts/git_add_check.sh
```

## 参数

- `--verbose`：输出每个文件的检查结果
- `--strict`：以下场景也会失败
  - 文件类型不支持
  - 对应语法检查工具不存在
- `--staged-only`：仅检查 staged 文件（默认行为）
- `-h, --help`：查看帮助

## 返回码

- `0`：全部通过
- `1`：至少一个文件语法检查失败（或严格模式下出现 skip）

## 说明

脚本读取的是 staged 版本内容，而非工作区版本，确保结果与即将提交的内容一致。

