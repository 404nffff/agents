---
name: codex-gateway-imagegen
description: 当用户在 Codex CLI 中要求生成图片、希望把图片保存为本地文件，或内置图像链路不可用而需要改走 Responses 兼容网关时使用。
---

# 网关图片生成

这个技能用于把 `prompt` 通过本技能本地 `.env` 中定义的网关配置，生成或编辑为图片文件。

它同时支持：

- 文生图
- 基于一张或多张参考图的图片编辑

## 快速开始

1. **确认任务类型**：文生图还是改图，并确认输出路径
2. **收集需求**：让用户描述主体、场景和画面方向
3. **风格确认**：主动询问是否需要风格库参考（必须询问）
4. **展示风格库**（如需要）：展示 `references/prompt.md`，同一轮任务只展示一次完整列表
5. **组织 prompt**：基于用户描述或选定风格编写完整 prompt
6. **选择尺寸**：
   - 方图：`1024x1024`
   - 竖图/手机截图：`1024x1536`
   - 横图：`1536x1024`
7. **配置网关**：确保 `skills/codex-gateway-imagegen/.env` 已配置（首次使用需从 `.env.example` 复制）
8. **执行生成**：运行 `scripts/generate_gateway_image.py`
9. **处理失败**：如遇 TLS/网络错误，在更高权限环境重试
10. **交付结果**：向用户报告最终图片保存路径

## 工作流

### 1. 先接收用户自然语言里的风格描述

默认流程：

- 先问清用户要生成什么或修改什么
- 如果主体、场景、情绪还不清楚，就继续补问
- 直接接受用户给出的风格描述，例如 `动漫风`、`电影感`、`极简海报`、`高级科技感`
- **在收到描述后，必须主动询问用户**：

  ```
  我已经收到你的描述。需要我提供风格库参考吗？
  
  - 如果需要，我会展示风格库列表供你选择
  - 如果不需要，我就直接按你的描述组织 prompt 并生成
  ```

风格编号不是强制要求。

用户可以通过以下任一种方式提供风格信息：

- 直接给关键词或自然语言风格描述
- 从 `references/prompt.md` 里选择编号

### 2. 需要时再使用风格参考库

`references/prompt.md` 是风格参考库，不是强制门槛。

适合使用它的场景：

- 用户明确说自己没想好画风
- 用户希望你推荐几个方向
- 用户给的是宽泛要求，例如 `做得高级一点`、`偏二次元一点`、`来几个风格方案`
- 你希望给出一组稳定的编号候选，方便用户快速选择

标准交互顺序：

1. 用户先描述图片需求
2. 你询问：是否需要风格库参考
3. 如果用户回答“需要”，则展示 `references/prompt.md`
4. 如果用户回答“不需要”，则直接基于用户描述写 `prompt`
5. 如果已经展示过一次完整风格库，后续同一轮任务里不要再次完整输出，只做简短引用、推荐编号或局部摘取

以下情况仍然不要主动要求编号：

- 用户已经给了明确风格
- 任务很简单，风格从需求里已经很明显
- 用户明确说不需要风格库参考

当你决定使用参考库时，使用统一的询问话术（与步骤 1 保持一致）：

```
我已经收到你的描述。需要我提供风格库参考吗？

- 如果需要，我会展示风格库列表供你选择
- 如果不需要，我就直接按你的描述组织 prompt 并生成
```

当用户选择”需要风格库参考”时，执行规则：

- **第一次**：输出完整风格库
- **第二次及以后**：不要再次整份输出，只能：
  - 推荐 2-3 个编号
  - 摘取相关风格的小范围条目
  - 根据前文已出现的风格编号继续收敛

如果用户给了多个编号，在最终 `prompt` 里要明确主风格和辅助风格。

### 3. 组织 `prompt`

写 `prompt` 时，要写成完整的制作说明，而非零散碎片。**必须包含**：

- **主体**：画面核心对象
- **场景**：环境与背景
- **视觉风格**：艺术风格、色调
- **构图**：视角、布局
- **光线**：光照效果
- **输出特征**：如 `livestream screenshot`、`poster`、`photorealistic`、`9:16 vertical`
- **UI 元素**（如需要）：覆盖层或屏幕元素

**特殊场景处理**：

- **App 截图感**：必须明确写出截图感，并描述画面里的覆盖元素
- **改图任务**：额外说明
  - 哪些部分要贴近参考图
  - 哪些部分需要修改
  - 是自由改风格，还是高保真保留原图结构

**风格映射规则**：

- 用户选了编号 → 把对应风格关键词映射回 `prompt`，同时写入中文意图和英文关键词
- 用户给了关键词 → 直接使用用户表述，并扩写成可执行的 `prompt`
- 用户明确不需要风格库 → 不要再推荐风格库，直接进入 `prompt` 组织和出图

### 4. 选择合法尺寸

**询问用户**：在生成前主动询问用户期望的尺寸，或提供参考选项

```
请选择图片尺寸，或直接告诉我你需要的尺寸：

1. 方图：1024x1024（适合头像、图标、社交媒体）
2. 竖图：1024x1536（适合手机截图、海报、故事）
3. 横图：1536x1024（适合横幅、桌面壁纸）
4. 自定义尺寸（请直接告诉我，如 1920x1080）
```

**默认规则**：如果用户未明确指定，根据构图需求智能选择

**错误处理**：如果网关返回 `Invalid size ... below the current minimum pixel budget`，直接增大尺寸，不要重试原尺寸。

### 5. 用脚本发起请求

先准备 `skills/codex-gateway-imagegen/.env`。最快的方式是从 `.env.example` 复制：

```dotenv
OPENAI_BASE_URL=https://your-gateway.example.com/v1
OPENAI_API_KEY=<your-api-key>
GATEWAY_IMAGEGEN_MODEL=gpt-5.4
GATEWAY_IMAGEGEN_TIMEOUT=600
GATEWAY_IMAGEGEN_SIZE=1024x1024
GATEWAY_IMAGEGEN_ACTION=auto
```

变量说明：

- `OPENAI_BASE_URL`：必填，网关基础地址，不要带 `/responses`
- `OPENAI_API_KEY`：必填
- `GATEWAY_IMAGEGEN_MODEL`：可选，默认模型
- `GATEWAY_IMAGEGEN_TIMEOUT`：可选，请求超时秒数
- `GATEWAY_IMAGEGEN_SIZE`：可选，默认尺寸
- `GATEWAY_IMAGEGEN_ACTION`：可选，默认动作，可选 `auto|generate|edit`

优先级：

- 命令行参数覆盖 `.env` 和进程环境变量
- `.env` 存在时作为这个技能的本地权威配置，不被宿主机进程环境变量覆盖
- 仅当默认 `.env` 不存在时，才回退读取进程环境变量

文生图示例：

```powershell
python scripts/generate_gateway_image.py --prompt "<prompt>" --out "<output-path>" --size 1024x1024
```

本地参考图改图示例：

```powershell
python scripts/generate_gateway_image.py --prompt "<prompt>" --image "<reference-image>" --action edit --out "<output-path>" --size 1024x1536
```

多参考图改图示例：

```powershell
python scripts/generate_gateway_image.py --prompt "<prompt>" --image "<reference-1>" --image "<reference-2>" --action edit --out "<output-path>" --size 1024x1536
```

可选参数：

- `--image <path>`：本地参考图，可重复传入
- `--image-url <url>`：远程参考图，可重复传入
- `--mask <path>`：局部编辑的 `mask` 图
- `--action auto|generate|edit`：默认 `auto`
- `--env-file <path>`：自定义 `.env` 文件路径，可用于任务级配置

脚本行为：

- 默认从 skill 根目录读取 `.env`
- 默认优先从 `.env` 解析 `OPENAI_BASE_URL` 和 `OPENAI_API_KEY`
- 当默认 `.env` 不存在时，才回退从进程环境变量解析配置
- 调用 `/responses`
- 默认使用 `model="gpt-5.4"`，也可以从 `GATEWAY_IMAGEGEN_MODEL` 覆盖
- 通过 `image_generation` 工具发起 `action=auto|generate|edit`
- 把 `prompt` 文本作为 `input_text`
- 把参考图作为 `input_image`
- 把可选 `mask` 作为 `input_image_mask`
- 把返回的 base64 图片解码并写入输出文件

重要说明：

- Responses 的主模型仍然是 `gpt-5.4` 这类文本模型
- 真正的出图和改图由 `image_generation` 工具完成
- 做编辑时，优先使用 `--action edit` 并至少提供一张 `--image`

### 6. 处理常见失败场景

**网络/TLS 错误**（优先判断为环境问题）：

- `Authentication failed, see inner exception`
- `schannel: AcquireCredentialsHandle failed`
- `The read operation timed out`

→ 用同样参数在更高网络权限下重新执行脚本

**HTTP 错误**：先查看错误体，再决定是否修改 `prompt`

**参考图遵循度不足**：

1. 增强 `prompt` 里的”保留原图”约束
2. 从 `auto` 改成 `edit`
3. 局部改动使用 `mask`

### 7. 保存输出文件

**文件命名规范**：使用有语义的文件名，直接保存到当前工作区

示例：
- `hero_poster.png`
- `livestream_vertical_v2.png`
- `product_mockup_square.png`

**禁止**：把最终产物只留在临时目录里

## 参考资料

- `references/prompt.md` 是可选风格参考库，适合在用户需要灵感、比较或编号候选时使用。
- 当请求失败、需要快速判断问题类型时，读取 `references/troubleshooting.md`。
