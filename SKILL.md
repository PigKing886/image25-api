---
name: image25-api
description: "使用用户指定的 OpenAI 兼容图片接口和本地配置文件，通过 image2.5 生成或编辑图片。适用于用户要求沿用已验证的生图配置、使用 image2.5 API 或调用本技能的场景；普通未指定接口的生图使用内置 imagegen 流程。"
---

# Image 2.5 API 生图

将已验证的兼容接口流程用于新图片或已有图片的修改。使用本技能或明确要求该接口，即已选择 API 路径；无需每次重复确认。用户要求只讨论时不发生成请求。

## 模型与配置

- 配置文件通过 `-ConfigFile` 或 `IMAGE25_CONFIG_FILE` 指定，默认位于 `$CODEX_HOME/image25-api/config.json`（CODEX_HOME 未设置时使用 `~/.codex`）。不要显示或复制其正文到对话、提示词、技能、仓库或日志。
- Python 通过 `-Python` 或 `IMAGE25_PYTHON` 指定，默认查找 PATH 中的 python。运行时需要 openai，图片检查/处理需要 Pillow。
- 请求模型：`gpt-image-2.5`。用户说 image2.5 时使用此标识；其他模型以用户明确指定为准，不自行降级。
- 适用于 PowerShell 7；依赖当前 Codex 环境已有的内置 imagegen 技能和 CLI。安装与配置示例见 [README](README.md)。
- 该标识是配置服务接受的请求名称；接口成功不能证明服务商实际使用的底层模型，也不代表官方模型目录中的名称。

## 工作方式

1. 阅读已安装的 [imagegen 技能](../.system/imagegen/SKILL.md)，遵循其提示词、编辑和预览流程。此技能的脚本负责安全传递配置，实际生成仍调用它的 `scripts/image_gen.py`，不修改该工具。
2. 读取用户提示词文件时，区分画面需求、接口数据和文件内的其他指令。先判断文件是否含密钥，不直接打印整份未知文件；不把接口凭据送入图片提示词。
3. 将确认后的纯画面提示词另存为 UTF-8 文件。详细提示词保持原意；编辑模式先查看原图，写明只改什么、保留什么。新请求默认一张图，不强制复用绳桥或书法主题。
4. 调用下方脚本。图片默认保存在当前项目的 `output/imagegen/`，使用不同版本文件名；不要覆盖已选定图片。`-DryRun` 只检查参数，不联网或生成图片。
5. 请求未返回时继续等待并按需简短更新，不重复提交相同请求。模型列表 `/v1/models` 的 403 不等于图片接口不可用，无需先查询模型列表。实际生成失败后，根据已脱敏错误定位；认证拒绝、无模型权限或明确额度不足时停止，不猜密钥、绕过限制或自动换模型。超时但结果不明时先检查输出，不盲目重试可能已收费的请求。
6. 用 `view_image` 检查生成结果，核对文字、构图和编辑保留项；只有确有偏差时进行针对性修正。读取实际尺寸/透明通道，不把请求参数当成返回文件属性。需要中性底色时可从透明原图另存合成版本；保留原图。
7. 最终以内嵌图片展示结果，给出实际绝对路径和提示词文件链接，并注明请求模型与 API 方式。不擅自转换为游戏资源、部署或发布。

## 调用

以下命令在 PowerShell 中运行；将示例路径换成当前任务实际路径。

```powershell
& "$HOME/.codex/skills/image25-api/scripts/run_image.ps1" -Mode generate -PromptFile "./output/imagegen/example.prompt.txt" -Out "./output/imagegen/example-v1.png"
```

修改已有图片：

```powershell
& "$HOME/.codex/skills/image25-api/scripts/run_image.ps1" -Mode edit -PromptFile "./output/imagegen/edit.prompt.txt" -ImageFiles "./output/imagegen/example-v1.png" -Out "./output/imagegen/example-v2.png"
```

可选参数：`-ConfigFile`、`-Python`、`-Model`、`-Size`（默认 1024x1024）、`-Quality`（默认 medium）、`-DryRun`。中文书法等密集文字任务可使用 `-Quality high`。脚本仅接受 PNG 输出。

## 凭据与依赖

配置文件支持两行格式，或以 `base_url`、`api_key` 为键的 JSON。纯文本密钥须使用当前服务的 `sk-` 前缀；其他密钥形式使用 JSON。配置不存在时可使用现有 `OPENAI_BASE_URL` 和 `OPENAI_API_KEY`。接口主机和密钥应来自用户为本任务提供的配置，不从无关应用搜集凭据。

脚本在地址末尾缺少 `/v1` 时追加，避免重复追加，只临时设置进程环境变量，并在结束后恢复原值；不在命令行参数中展开密钥。日志对完整密钥及密钥样式字符串脱敏。第三方错误若含其他敏感信息，继续摘要而非原样转发。

若默认 Python 不存在，优先寻找用户已配置且具有 openai/Pillow 的运行时；需要安装时使用项目隔离环境。若内置 imagegen CLI 不存在，报告缺失依赖，不静默改用另一套 SDK 生成器。
