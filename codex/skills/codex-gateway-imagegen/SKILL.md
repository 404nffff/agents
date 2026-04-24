---
name: codex-gateway-imagegen
description: Generate raster images through the Responses-compatible gateway already configured for Codex, then save the result into the current workspace. Use when a user asks for image generation in Codex CLI, wants the output as a local file, or when the built-in image path is unavailable and the session must call the configured gateway directly.
---

# Codex Gateway Imagegen

Use this skill to turn a prompt into an image file through the gateway defined in the skill-local `.env` file.

It supports both:

- text-to-image generation
- image editing with one or more reference images

## Quick Start

1. Before writing any prompt, read `references/prompt.md`, show the style list to the user, and ask the user to reply with the desired style number.
2. Confirm whether the user wants generation or editing, then confirm the output path.
3. Choose a size that matches the target:
   - Square image: `1024x1024`
   - Portrait / phone screenshot: `1024x1536`
   - Landscape: `1536x1024`
4. Copy `codex/skills/codex-gateway-imagegen/.env.example` to `codex/skills/codex-gateway-imagegen/.env` and fill in the real gateway values.
5. Run `scripts/generate_gateway_image.py`.
6. If the request fails inside the sandbox with TLS, schannel, or read-timeout errors, rerun the same command with escalated host-network access.
7. Report the saved file path.

## Workflow

### 1. Ask for the style number first

This step is mandatory for every image request.

Before you draft the final prompt, you must:

- read `references/prompt.md`
- show the numbered style list to the user
- ask the user to reply with one or more style numbers
- wait for the user's answer before generating the final prompt

Required interaction rules:

- Even if the user already says something like `动漫风` or `赛博朋克`, still show the style list and ask for the number to confirm
- If the user gives multiple numbers, combine those styles in the final prompt with a clear primary style and secondary accents
- If the user says `不确定`, recommend 3 suitable numbers based on the task, then ask the user to pick one

Use this reply pattern:

```markdown
先选画风编号。请从 `codex/skills/codex-gateway-imagegen/references/prompt.md` 的风格列表里回复编号，例如：`03`、`19`、`25`。

如果你不确定，我可以先根据你的用途推荐 3 个编号给你选。
```

When presenting the style list, tell the user the list comes from `references/prompt.md`, and ask them to input the number directly.

### 2. Shape the prompt

Write the prompt as a production spec, not a fragment. Include:

- Subject
- Scene
- Visual style
- Composition
- Lighting
- Output cues such as `livestream screenshot`, `poster`, `photorealistic`, `9:16 vertical`
- UI overlays or exact on-screen elements when needed

If the user wants a live-app screenshot feel, say so explicitly and describe the overlays.

If the user wants editing, also describe:

- what should stay close to the reference image
- what should change
- whether the edit is loose restyling or high-fidelity preservation

When a style number is selected, map it back to the style keywords in `references/prompt.md` and include both the Chinese style intent and the English keywords in the final prompt.

### 3. Pick a legal size

Default to `1024x1024` unless the composition clearly needs another aspect ratio.

Known-good sizes from this workflow:

- `1024x1024`
- `1024x1536`

If the gateway returns an error like `Invalid size ... below the current minimum pixel budget`, increase the requested size instead of retrying the same one.

### 4. Generate with the helper script

Create `codex/skills/codex-gateway-imagegen/.env` first. The fastest path is copying `.env.example`:

```dotenv
OPENAI_BASE_URL=https://your-gateway.example.com/v1
OPENAI_API_KEY=<your-api-key>
GATEWAY_IMAGEGEN_MODEL=gpt-5.4
GATEWAY_IMAGEGEN_TIMEOUT=600
GATEWAY_IMAGEGEN_SIZE=1024x1024
GATEWAY_IMAGEGEN_ACTION=auto
```

Variable notes:

- `OPENAI_BASE_URL`: required, the gateway base URL without the trailing `/responses`
- `OPENAI_API_KEY`: required
- `GATEWAY_IMAGEGEN_MODEL`: optional default model
- `GATEWAY_IMAGEGEN_TIMEOUT`: optional default timeout in seconds
- `GATEWAY_IMAGEGEN_SIZE`: optional default size
- `GATEWAY_IMAGEGEN_ACTION`: optional default action, one of `auto|generate|edit`

Priority:

- CLI arguments override environment variables and `.env`
- Process environment variables override values from `.env`
- `.env` provides the default local configuration for this skill

For text-to-image:

```powershell
python scripts/generate_gateway_image.py --prompt "<prompt>" --out "<output-path>" --size 1024x1024
```

For image editing with a local reference image:

```powershell
python scripts/generate_gateway_image.py --prompt "<prompt>" --image "<reference-image>" --action edit --out "<output-path>" --size 1024x1536
```

For image editing with multiple references:

```powershell
python scripts/generate_gateway_image.py --prompt "<prompt>" --image "<reference-1>" --image "<reference-2>" --action edit --out "<output-path>" --size 1024x1536
```

Optional inputs:

- `--image <path>`: local reference image, repeatable
- `--image-url <url>`: remote reference image, repeatable
- `--mask <path>`: local mask image for targeted edit regions
- `--action auto|generate|edit`: defaults to `auto`
- `--env-file <path>`: optional custom env file path, useful if you want to point to a file such as `.evn` or a task-specific config

The script:

- Reads `.env` from the skill root by default
- Resolves `OPENAI_BASE_URL` and `OPENAI_API_KEY` from `.env` or process environment
- Calls `/responses`
- Uses `model="gpt-5.4"` by default, or the value from `GATEWAY_IMAGEGEN_MODEL`
- Requests the `image_generation` tool with `action=auto|generate|edit`
- Sends prompt text as `input_text`
- Sends reference images as `input_image`
- Sends an optional mask as `input_image_mask`
- Decodes the returned base64 image and writes the output file

Important:

- The Responses `model` remains the main model such as `gpt-5.4`
- Image generation and editing are performed through the `image_generation` tool
- For editing, prefer `--action edit` and include at least one `--image`

### 5. Handle the common failure modes

If the call fails inside the sandbox with networking or TLS symptoms such as:

- `Authentication failed, see inner exception`
- `schannel: AcquireCredentialsHandle failed`
- `The read operation timed out`

then treat that as an environment-path problem first, not necessarily a gateway problem. Rerun the same script outside the sandbox with escalated host-network access.

If the call reaches the gateway and returns an HTTP error body, inspect the body before changing the prompt.

If the result ignores the reference image too loosely:

- strengthen the prompt with explicit preservation instructions
- switch from `auto` to `edit`
- use a mask when only part of the image should change

### 6. Save outputs deliberately

If the user asked for an image for the current task, save it directly into the current workspace with a descriptive name such as:

- `hero_poster.png`
- `livestream_vertical_v2.png`
- `product_mockup_square.png`

Do not leave the final asset only in a temp location.

## References

- Read `references/prompt.md` before every image generation request and use it as the canonical style-number list shown to the user.
- Read `references/troubleshooting.md` when the request fails and you need the quick decision tree.
