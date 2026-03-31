# React 最佳实践

这是一个结构化仓库，用于创建和维护面向智能体与 LLM 优化的 React 最佳实践。

## 目录结构

- `rules/`：规则文件目录（每个规则一个文件）
  - `_sections.md`：分区元数据（标题、影响级别、说明）
  - `_template.md`：新建规则的模板文件
  - `area-description.md`：单条规则文件
- `src/`：构建脚本与工具函数
- `metadata.json`：文档元数据（版本、组织、摘要）
- __`AGENTS.md`__：编译输出文件（自动生成）
- __`test-cases.json`__：用于 LLM 评估的测试用例（自动生成）

## 快速开始

1. 安装依赖：
   ```bash
   pnpm install
   ```

2. 从规则生成 `AGENTS.md`：
   ```bash
   pnpm build
   ```

3. 校验规则文件：
   ```bash
   pnpm validate
   ```

4. 提取测试用例：
   ```bash
   pnpm extract-tests
   ```

## 新建规则

1. 复制 `rules/_template.md` 为 `rules/area-description.md`
2. 选择合适的领域前缀：
   - `async-`：消除请求瀑布（第 1 节）
   - `bundle-`：包体积优化（第 2 节）
   - `server-`：服务端性能（第 3 节）
   - `client-`：客户端数据获取（第 4 节）
   - `rerender-`：重复渲染优化（第 5 节）
   - `rendering-`：渲染性能（第 6 节）
   - `js-`：JavaScript 性能（第 7 节）
   - `advanced-`：高级模式（第 8 节）
3. 填写 frontmatter 和正文内容
4. 确保示例清晰且包含解释说明
5. 运行 `pnpm build` 重新生成 `AGENTS.md` 和 `test-cases.json`

## 规则文件结构

每个规则文件都应遵循如下结构：

````markdown
---
title: 规则标题
impact: MEDIUM
impactDescription: 可选说明
tags: tag1, tag2, tag3
---

## 规则标题

简要说明这条规则及其重要性。

**错误示例（说明问题点）：**

```typescript
// 错误代码示例
```

**正确示例（说明改进点）：**

```typescript
// 正确代码示例
```

示例后的补充说明（可选）。

参考资料：[链接](https://example.com)
````

## 文件命名规范

- 以 `_` 开头的文件为特殊文件（构建时会忽略）
- 规则文件命名格式：`area-description.md`（例如 `async-parallel.md`）
- 分区会根据文件名前缀自动推断
- 每个分区内的规则按标题字母顺序自动排序
- 规则 ID（如 1.1、1.2）会在构建时自动生成

## 影响级别

- `CRITICAL`：最高优先级，性能收益显著
- `HIGH`：高收益性能优化
- `MEDIUM-HIGH`：中高收益优化
- `MEDIUM`：中等收益优化
- `LOW-MEDIUM`：中低收益优化
- `LOW`：增量优化

## 脚本命令

- `pnpm build`：将规则编译为 `AGENTS.md`
- `pnpm validate`：校验所有规则文件
- `pnpm extract-tests`：提取用于 LLM 评估的测试用例
- `pnpm dev`：执行构建与校验

## 贡献说明

新增或修改规则时，请遵循：

1. 使用与你分区对应的文件名前缀
2. 按 `_template.md` 结构编写内容
3. 提供清晰的错误/正确示例并附解释
4. 添加合适的标签
5. 运行 `pnpm build` 重新生成 `AGENTS.md` 和 `test-cases.json`
6. 规则会按标题自动排序，无需手动维护编号

## 致谢

本项目最初由 [@shuding](https://x.com/shuding) 在 [Vercel](https://vercel.com) 创建。
