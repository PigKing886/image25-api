# Image 2.5 API 生图技能

为 Codex 提供可复用的 OpenAI 兼容图片 API 工作流，支持生成、编辑、本地配置读取、密钥脱敏及图片预览。默认请求模型 `gpt-image-2.5`，可通过 `-Model` 覆盖。

模型名是服务商接受的请求标识，不代表对底层模型身份或官方可用性的保证。使用者需自行提供兼容接口及凭据；仓库不附带接口账号、密钥或额度。

## 环境要求

- PowerShell 7、Python 3，以及 Python 包 `openai`、`Pillow`。
- Codex 的内置 `imagegen` 技能及 `skills/.system/imagegen/scripts/image_gen.py`。本仓库通过该 CLI 调用图片接口，不打包或修改其源码。
- Codex 技能目录默认是 `~/.codex/skills`；设置了 `CODEX_HOME` 时使用对应目录。

## 安装

```powershell
$codexDirectory = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
git clone https://github.com/PigKing886/image25-api.git "$codexDirectory/skills/image25-api"
```

如果目标目录已有同名技能，先保存自己的修改，再选择更新方式，不要直接覆盖个人配置。

为技能建立独立 Python 环境（Windows）：

```powershell
python -m venv "$codexDirectory/image25-api/.venv"
& "$codexDirectory/image25-api/.venv/Scripts/python.exe" -m pip install openai pillow
$env:IMAGE25_PYTHON = "$codexDirectory/image25-api/.venv/Scripts/python.exe"
```

上述环境变量仅作用于当前进程；也可在每次调用时使用 `-Python` 指定已有环境。其他 PowerShell 7 平台请使用虚拟环境对应的 Python 路径。

## 配置

将 `config.example.json` 复制到 `$codexDirectory/image25-api/config.json`，在本地填写地址与密钥：

```json
{
  "base_url": "https://your-provider.example/v1",
  "api_key": "YOUR_API_KEY"
}
```

也支持两行纯文本配置：第一行是接口地址，第二行是 `sk-` 开头的密钥。通过 `-ConfigFile` 或 `IMAGE25_CONFIG_FILE` 指定文件；没有配置文件时可使用 `OPENAI_BASE_URL` 和 `OPENAI_API_KEY`。

配置文件保留在仓库外，不上传 GitHub。地址会在缺少 `/v1` 后缀时自动追加。脚本临时设置环境变量并在结束后恢复，不把密钥放在命令行参数或日志中。

## 使用

在 Codex 中：

> 使用 $image25-api，按照这份提示词生成一张图片，并给我看预览。

直接运行：

```powershell
& "$codexDirectory/skills/image25-api/scripts/run_image.ps1" -Mode generate -PromptFile './prompt.txt' -Out './output/imagegen/example-v1.png'
```

修改已有图片：

```powershell
& "$codexDirectory/skills/image25-api/scripts/run_image.ps1" -Mode edit -ImageFiles './output/imagegen/example-v1.png' -PromptFile './edit-prompt.txt' -Out './output/imagegen/example-v2.png'
```

提示词文件使用 UTF-8。默认参数：1024×1024、medium、PNG、一张图片。文字较多时可加 `-Quality high`。不覆盖已有输出，使用新的版本文件名。服务商可能返回不同尺寸，生成后以实际文件为准。

加 `-DryRun` 可检查参数，不联网生成图片。脚本支持 `-ConfigFile`、`-Python`、`-Model`、`-Size`、`-Quality`。

## 错误处理与验证

查询 `/v1/models` 被拒绝，不足以判断图片接口不可用；本技能直接调用生成或编辑接口。实际认证、权限或额度错误应先解决，不自动切换模型。超时可能不代表服务端未完成，不应盲目重复提交。

在一次已有配置的实际使用中，生成与编辑请求已成功。可移植脚本另通过不联网测试，覆盖根地址和 `/v1` 地址规范化、文本/JSON 配置、日志脱敏、成功和失败后的环境变量恢复。不同服务商的兼容性需实际验证。

`tests/smoke.ps1` 使用本地假接口程序，不联网、不消耗生图额度：

```powershell
pwsh -File ./tests/smoke.ps1
```
